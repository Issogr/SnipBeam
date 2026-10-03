import AppKit
import ScreenCaptureKit

@MainActor
final class SelectionWindowController {
    private var windows: [SelectionWindow] = []
    private var keyMonitor: Any?
    private var completion: ((CaptureRegion?) -> Void)?

    func begin(displays: [SCDisplay], completion: @escaping (CaptureRegion?) -> Void) throws {
        self.completion = completion
        for screen in NSScreen.screens {
            guard let display = displays.first(where: { $0.displayID == CoordinateConverter.displayID(for: screen) }) else { continue }
            let window = SelectionWindow(screen: screen)
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(.group)
            view.setAccessibilityLabel("Select a screen region")
            view.setAccessibilityHelp("Drag a rectangle of at least 20 by 20 points. Press Escape to cancel.")
            view.onSelection = { [weak self] rect in
                guard let region = CoordinateConverter.region(localSelection: rect, screen: screen, display: display) else {
                    NSSound.beep()
                    return
                }
                self?.finish(region)
            }
            view.onCancel = { [weak self] in self?.cancel() }
            window.contentView = view
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        }
        guard !windows.isEmpty else {
            self.completion = nil
            throw CaptureError.message("No connected display is available. Connect a display and choose Select Region again.")
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func cancel() { finish(nil) }

    private func finish(_ region: CaptureRegion?) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for window in windows { window.close() }
        windows.removeAll()
        let callback = completion
        completion = nil
        callback?(region)
    }
}
