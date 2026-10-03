import CoreVideo
import Metal
import QuartzCore

// Mutable state is confined to queue; CAMetalLayer supports off-main drawable presentation.
final class FrameRenderer: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.example.SnipBeam.frames", qos: .userInteractive)
    private let layer: CAMetalLayer
    private let commands: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let cache: CVMetalTextureCache
    private let gpuAvailable = DispatchSemaphore(value: 1)
    // Accessed only on queue. Keeping the CV objects alive prevents IOSurface reuse by SCK.
    private var latest: (CVPixelBuffer, CVMetalTexture, MTLTexture)?
    private var needsDraw = false
    private var receivedFrames = 0
    private var presentedFrames = 0
    private var gpuFailures = 0
    private var lastDrawableSize = CGSize.zero
    private var active = true
    private var failureHandler: (@Sendable (String) -> Void)?
    private var reportedFailure = false

    func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) {
        queue.async { self.failureHandler = handler }
    }

    func deactivate() {
        queue.async {
            self.active = false
            self.latest = nil
            CVMetalTextureCacheFlush(self.cache, 0)
        }
    }

    func statistics() async -> (received: Int, presented: Int, failures: Int, size: CGSize, drawableSize: CGSize) {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: (self.receivedFrames, self.presentedFrames, self.gpuFailures,
                    CGSize(width: self.latest?.2.width ?? 0, height: self.latest?.2.height ?? 0), self.lastDrawableSize))
            }
        }
    }

    init(layer: CAMetalLayer, device: MTLDevice) throws {
        self.layer = layer
        guard let commands = device.makeCommandQueue() else {
            throw CaptureError.message("Metal could not create a command queue. Try reopening SnipBeam.")
        }
        self.commands = commands
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else {
            throw CaptureError.message("Metal could not create a texture cache.")
        }
        self.cache = cache
        // ponytail: compile once at launch; no separate Metal compiler or Xcode installation needed.
        let library = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        struct Vertex { float4 position [[position]]; float2 uv; };
        vertex Vertex previewVertex(uint id [[vertex_id]]) {
            const float2 p[] = { {-1, 1}, {-1, -1}, {1, 1}, {1, -1} };
            const float2 uv[] = { {0, 0}, {0, 1}, {1, 0}, {1, 1} };
            return { float4(p[id], 0, 1), uv[id] };
        }
        fragment float4 previewFragment(Vertex v [[stage_in]], texture2d<float> image [[texture(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return float4(image.sample(s, v.uv).rgb, 1);
        }
        """, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "previewVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "previewFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // ScreenCaptureKit calls this directly on queue; frames never hop through the main queue.
    func receive(_ pixels: CVPixelBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard active else { return }
        var image: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixels, nil, .bgra8Unorm,
                CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels), 0, &image) == kCVReturnSuccess,
              let image, let texture = CVMetalTextureGetTexture(image) else {
            fail("Metal could not map a captured frame. Close the preview and select the region again.")
            return
        }
        latest = (pixels, image, texture)
        receivedFrames += 1
        needsDraw = true
        draw()
    }

    func redraw() {
        queue.async { [weak self] in
            self?.needsDraw = true
            self?.draw()
        }
    }

    private func draw() {
        guard active, needsDraw, let latest, gpuAvailable.wait(timeout: .now()) == .success else { return }
        guard let drawable = layer.nextDrawable(), let command = commands.makeCommandBuffer() else {
            gpuAvailable.signal()
            return
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            gpuAvailable.signal()
            return
        }
        lastDrawableSize = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        encoder.setViewport(Self.viewport(imageSize: CGSize(width: latest.2.width, height: latest.2.height),
                                          drawableSize: lastDrawableSize))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(latest.2, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        needsDraw = false
        command.present(drawable)
        command.addCompletedHandler { [weak self, gpuAvailable] command in
            withExtendedLifetime(latest) {}
            gpuAvailable.signal()
            let failed = command.status == .error
            self?.queue.async { [weak self] in
                guard let self else { return }
                if failed {
                    self.gpuFailures += 1
                    self.fail("The GPU could not render the preview. Close the preview and select the region again.")
                } else { self.presentedFrames += 1 }
                self.draw()
            }
        }
        command.commit()
    }

    private func fail(_ message: String) {
        guard active, !reportedFailure else { return }
        reportedFailure = true
        failureHandler?(message)
    }

    static func viewport(imageSize: CGSize, drawableSize: CGSize) -> MTLViewport {
        let scale = min(drawableSize.width / imageSize.width, drawableSize.height / imageSize.height)
        let width = imageSize.width * scale, height = imageSize.height * scale
        return MTLViewport(originX: (drawableSize.width - width) / 2, originY: (drawableSize.height - height) / 2,
                           width: width, height: height, znear: 0, zfar: 1)
    }
}
