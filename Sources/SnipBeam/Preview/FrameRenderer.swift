import CoreVideo
import Metal
import QuartzCore

// Mutable state is confined to queue; CAMetalLayer supports off-main drawable presentation.
final class FrameRenderer: @unchecked Sendable {
    // CPU code never writes these capture buffers. GPU completion only releases this immutable lease.
    private struct InFlightFrame: @unchecked Sendable {
        let pixels: CVPixelBuffer
        let image: CVMetalTexture
    }

    let queue = DispatchQueue(label: "com.example.SnipBeam.frames", qos: .userInteractive, autoreleaseFrequency: .workItem)
    private let layer: CAMetalLayer
    private let commands: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let cache: CVMetalTextureCache
    private let gpuAvailable = DispatchSemaphore(value: 1)
    private let pass = MTLRenderPassDescriptor()
    // Accessed only on queue. Keeping the CV objects alive prevents IOSurface reuse by SCK.
    private var latest: CVPixelBuffer?
    private var texture: (CVMetalTexture, MTLTexture)?
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
            self.texture = nil
            CVMetalTextureCacheFlush(self.cache, 0)
        }
    }

    func statistics() async -> (received: Int, presented: Int, failures: Int, size: CGSize, drawableSize: CGSize) {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: (self.receivedFrames, self.presentedFrames, self.gpuFailures,
                    self.latest.map { CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0)) } ?? .zero,
                    self.lastDrawableSize))
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
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
    }

    // ScreenCaptureKit calls this directly on queue; frames never hop through the main queue.
    func receive(_ pixels: CVPixelBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard active else { return }
        latest = pixels
        texture = nil
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
        // Map only the newest frame when a drawable and GPU slot are available; dropped frames cost no texture work.
        if texture == nil {
            var image: CVMetalTexture?
            guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, latest, nil, .bgra8Unorm,
                    CVPixelBufferGetWidth(latest), CVPixelBufferGetHeight(latest), 0, &image) == kCVReturnSuccess,
                  let image, let metalTexture = CVMetalTextureGetTexture(image) else {
                gpuAvailable.signal()
                fail("Metal could not map a captured frame. Close the preview and select the region again.")
                return
            }
            texture = (image, metalTexture)
        }
        guard let texture else { gpuAvailable.signal(); return }
        pass.colorAttachments[0].texture = drawable.texture
        // The encoder retains the target; don't hold a drawable's texture between frames.
        defer { pass.colorAttachments[0].texture = nil }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            gpuAvailable.signal()
            return
        }
        lastDrawableSize = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        encoder.setViewport(Self.viewport(imageSize: CGSize(width: texture.1.width, height: texture.1.height),
                                          drawableSize: lastDrawableSize))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture.1, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        needsDraw = false
        command.present(drawable)
        let inFlight = InFlightFrame(pixels: latest, image: texture.0)
        command.addCompletedHandler { [weak self, gpuAvailable] command in
            withExtendedLifetime(inFlight) {}
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
