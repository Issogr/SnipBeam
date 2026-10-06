import AppKit

@MainActor
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    let preview: MetalPreviewView
    var onClose: (() -> Void)?

    init(size: CGSize) throws {
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let scale = min(1, min(available.width * 0.8 / size.width, available.height * 0.8 / size.height))
        let initialSize = CGSize(width: max(160, size.width * scale), height: max(100, size.height * scale))
        preview = try MetalPreviewView(previewSize: initialSize)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: initialSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SnipBeam"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 160, height: 100)
        window.contentView = preview
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func setTitleBarHidden(_ hidden: Bool) {
        guard let window else { return }
        window.titleVisibility = hidden ? .hidden : .visible
        window.titlebarAppearsTransparent = hidden
        // Keep the titled window discoverable by conferencing apps while the preview fills its frame.
        if hidden { window.styleMask.insert(.fullSizeContentView) }
        else { window.styleMask.remove(.fullSizeContentView) }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = hidden
        }
        window.isMovableByWindowBackground = hidden
    }

    func setPaused(_ paused: Bool) { window?.subtitle = paused ? "Paused" : "" }
    func windowWillClose(_ notification: Notification) {
        preview.renderer?.deactivate()
        onClose?()
    }
    func windowDidDeminiaturize(_ notification: Notification) { preview.renderer?.redraw() }
    func windowDidChangeOcclusionState(_ notification: Notification) { preview.renderer?.redraw() }
    func windowDidEndLiveResize(_ notification: Notification) { preview.renderer?.redraw() }
}
