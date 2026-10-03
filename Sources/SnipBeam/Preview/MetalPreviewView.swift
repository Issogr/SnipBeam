import MetalKit

final class MetalPreviewView: MTKView, MTKViewDelegate {
    private(set) var renderer: FrameRenderer?

    init(previewSize: CGSize) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CaptureError.message("SnipBeam needs a Metal-capable GPU. No Metal device is available.")
        }
        super.init(frame: CGRect(origin: .zero, size: previewSize), device: device)
        colorPixelFormat = .bgra8Unorm
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        framebufferOnly = true
        // MTKView owns sizing/backing scale; the capture queue renders to its CAMetalLayer.
        isPaused = true
        enableSetNeedsDisplay = false
        autoResizeDrawable = true
        guard let metalLayer = layer as? CAMetalLayer else {
            throw CaptureError.message("Could not create the Metal preview surface.")
        }
        metalLayer.isOpaque = true
        metalLayer.maximumDrawableCount = 2
        metalLayer.allowsNextDrawableTimeout = true
        renderer = try FrameRenderer(layer: metalLayer, device: device)
        delegate = self
    }

    @available(*, unavailable, message: "Use init(previewSize:); SnipBeam has no nibs or storyboards.")
    required init(coder: NSCoder) { super.init(coder: coder) }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // MTKView calls this before updating its layer. Publish the size before off-main drawing,
        // including while paused, when no subsequent capture frame would otherwise repair the resize.
        (layer as? CAMetalLayer)?.drawableSize = size
        renderer?.redraw()
    }
    func draw(in view: MTKView) { renderer?.redraw() }
}
