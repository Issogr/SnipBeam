import AppKit
import ScreenCaptureKit

// Opt-in check of the real app controls: packaged executable --smoke-test.
// Everything stays in memory; no screenshots or frames are written to disk.
@MainActor
enum CaptureSmokeTest {
    static func run(appDelegate app: AppDelegate) async {
        setbuf(stdout, nil)
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            print("FAIL: capture smoke check timed out after 30 seconds")
            exit(1)
        }
        do {
            try require(CGPreflightScreenCaptureAccess(), "Grant SnipBeam Screen Recording permission before running the smoke check.")
            let content = try await ScreenCaptureManager.content()
            let screens = NSScreen.screens.filter { screen in content.displays.contains { $0.displayID == CoordinateConverter.displayID(for: screen) } }
            try require(!screens.isEmpty, "No display is available.")
            print("Checking \(screens.count) display(s)…")
            for screen in screens {
                // Start and cancel using the real menu callback and overlay key handler.
                app.menuBar?.onSelect?()
                try await wait(app)
                let cancelledView = try overlay(on: screen)
                let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: cancelledView.window!.windowNumber, context: nil, characters: "\u{1b}",
                    charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
                cancelledView.keyDown(with: escape)
                try require(!app.state.isSelecting && app.state.region == nil, "Escape did not cancel selection.")

                app.menuBar?.onSelect?()
                try await wait(app)
                let view = try overlay(on: screen)
                let start = CGPoint(x: 80, y: 80)
                let end = CGPoint(x: min(720, view.bounds.width), y: min(440, view.bounds.height))
                func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                        windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                view.mouseDown(with: event(.leftMouseDown, start))
                view.mouseDragged(with: event(.leftMouseDragged, end))
                view.mouseUp(with: event(.leftMouseUp, end))
                try await wait(app)
                guard let region = app.state.region, let preview = app.preview, let renderer = preview.preview.renderer else {
                    throw CaptureError.message("Dragging did not start capture.")
                }
                try await Task.sleep(for: .seconds(1))
                let initial = await renderer.statistics()
                try require(initial.received > 0 && initial.presented > 0 && initial.failures == 0,
                            "No frames reached the Metal drawable, or the GPU reported an error.")
                try require(initial.size == CGSize(width: region.pixelWidth, height: region.pixelHeight), "Capture pixel size does not match the selected region.")
                let windows = try await ScreenCaptureManager.content().windows
                try require(windows.contains { $0.windowID == CGWindowID(preview.window!.windowNumber) && $0.title == "SnipBeam" && $0.windowLayer == 0 },
                            "SnipBeam was not discoverable as a normal shareable window.")

                app.menuBar?.onPause?()
                try await wait(app)
                try require(app.state.isPaused, "The Pause control did not change state.")
                try await Task.sleep(for: .milliseconds(200))
                let paused = await renderer.statistics()
                preview.window?.setContentSize(CGSize(width: 400, height: 400))
                app.menuBar?.onCursor?()
                try await wait(app)
                try await Task.sleep(for: .milliseconds(300))
                let resized = await renderer.statistics()
                try require(resized.received == paused.received && resized.size == initial.size,
                            "Pause or resize changed the captured frames.")
                try require(resized.presented > paused.presented && resized.drawableSize == preview.preview.drawableSize,
                            "Paused preview did not redraw at the new drawable size: presented \(paused.presented) → \(resized.presented), drawn \(resized.drawableSize), expected \(preview.preview.drawableSize).")

                app.menuBar?.onPause?()
                try await wait(app)
                app.menuBar?.onCursor?()
                try await wait(app)
                try await Task.sleep(for: .seconds(1))
                let resumed = await renderer.statistics()
                try require(!app.state.isPaused && resumed.received > paused.received && resumed.failures == 0,
                            "Resume did not restart frame delivery.")
                preview.window?.performClose(nil)
                try await wait(app)
                try require(app.state.region == nil && app.preview == nil, "Closing the preview did not stop capture.")
                let closed = await renderer.statistics()
                try await Task.sleep(for: .milliseconds(200))
                let stopped = await renderer.statistics()
                try require(closed.received == stopped.received, "Frames kept arriving after preview close.")
                print("PASS: display \(region.display.displayID), scale \(region.pixelScale), \(resumed.size), \(resumed.received) frames, \(resumed.presented) presentations; selection/Escape, shareable window, resize, pause/resume, cursor updates, close")
            }
            print("Capture smoke check completed.")
            NSApp.terminate(nil)
        } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func wait(_ app: AppDelegate) async throws {
        while app.busy { try await Task.sleep(for: .milliseconds(20)) }
    }

    private static func overlay(on screen: NSScreen) throws -> SelectionView {
        guard let window = NSApp.windows.compactMap({ $0 as? SelectionWindow }).first(where: { $0.isVisible && $0.frame == screen.frame }),
              let view = window.contentView as? SelectionView else {
            throw CaptureError.message("No selection overlay on the requested display.")
        }
        return view
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CaptureError.message(message) }
    }
}
