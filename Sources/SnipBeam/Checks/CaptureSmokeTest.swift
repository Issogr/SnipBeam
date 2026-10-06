import AppKit
import ScreenCaptureKit
import Security

// Opt-in check of the real app controls: packaged executable --smoke-test.
// Everything stays in memory; no screenshots or frames are written to disk.
@MainActor
enum CaptureSmokeTest {
    static func run(appDelegate app: AppDelegate) async {
        setbuf(stdout, nil)
        let profiling = CommandLine.arguments.contains("--performance-test")
        DispatchQueue.global().asyncAfter(deadline: .now() + (profiling ? 120 : 30)) {
            print("FAIL: capture check timed out")
            exit(1)
        }
        do {
            let savedTitleBarPreference = UserDefaults.standard.object(forKey: "hidesTitleBar")
            let savedCursorPreference = UserDefaults.standard.object(forKey: "showsCursor")
            defer {
                UserDefaults.standard.set(savedTitleBarPreference, forKey: "hidesTitleBar")
                UserDefaults.standard.set(savedCursorPreference, forKey: "showsCursor")
            }
            if UserDefaults.standard.bool(forKey: "hidesTitleBar") { app.menuBar?.onTitleBar?() }
            guard let task = SecTaskCreateFromSelf(nil) else { throw CaptureError.message("Could not inspect code-signing entitlements.") }
            try require(SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool == true,
                        "The packaged app is not sandboxed.")
            if let path = ProcessInfo.processInfo.environment["SNIPBEAM_SANDBOX_PROBE"] {
                let result = access(path, R_OK)
                try require(result == -1 && (errno == EPERM || errno == EACCES), "Sandbox allowed access to the external test fixture.")
                print("PASS: sandbox denies access to the external test fixture")
            }
            try require(CGPreflightScreenCaptureAccess(), "Grant SnipBeam Screen Recording permission before running the smoke check.")
            if profiling { try await ResourceMeasurement.measure("idle") }
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
                try select(on: screen)
                try await wait(app)
                guard let region = app.state.region, let preview = app.preview, let renderer = preview.preview.renderer else {
                    throw CaptureError.message("Dragging did not start capture.")
                }
                try await Task.sleep(for: .seconds(1))
                let initial = await renderer.statistics()
                try require(initial.received > 0 && initial.presented > 0 && initial.failures == 0,
                            "No frames reached the Metal drawable, or the GPU reported an error.")
                try require(initial.size == CGSize(width: region.pixelWidth, height: region.pixelHeight), "Capture pixel size does not match the selected region.")
                if profiling { try await ResourceMeasurement.measure("capturing", renderer: renderer) }
                let window = preview.window!
                let windowNumber = window.windowNumber
                let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
                app.menuBar?.onTitleBar?()
                try require(UserDefaults.standard.bool(forKey: "hidesTitleBar") &&
                            window.titleVisibility == .hidden && window.titlebarAppearsTransparent &&
                            buttons.allSatisfy { window.standardWindowButton($0)?.isHidden == true } &&
                            preview.preview.frame.size == window.frame.size && preview.preview.mouseDownCanMoveWindow,
                            "Hide Title Bar did not produce a draggable, full-window preview without controls.")
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
                if profiling { try await ResourceMeasurement.measure("paused", renderer: renderer) }

                app.menuBar?.onTitleBar?()
                try require(!UserDefaults.standard.bool(forKey: "hidesTitleBar") &&
                            window.titleVisibility == .visible && !window.titlebarAppearsTransparent &&
                            !window.styleMask.contains(.fullSizeContentView) &&
                            buttons.allSatisfy { window.standardWindowButton($0)?.isHidden == false } &&
                            preview.preview.frame.height < window.frame.height && window.subtitle == "Paused" &&
                            window.windowNumber == windowNumber,
                            "Restoring the title bar did not restore controls on the same paused preview.")

                app.menuBar?.onPause?()
                try await wait(app)
                app.menuBar?.onCursor?()
                try await wait(app)
                try await Task.sleep(for: .seconds(1))
                let resumed = await renderer.statistics()
                try require(!app.state.isPaused && resumed.received > paused.received && resumed.failures == 0,
                            "Resume did not restart frame delivery.")
                if profiling {
                    let cover = NSWindow(contentRect: preview.window!.frame, styleMask: .borderless, backing: .buffered, defer: false)
                    cover.isReleasedWhenClosed = false
                    cover.backgroundColor = .darkGray
                    cover.level = .floating
                    cover.orderFrontRegardless()
                    try await ResourceMeasurement.measure("covered preview", renderer: renderer)
                    cover.close()
                    preview.window?.miniaturize(nil)
                    try await ResourceMeasurement.measure("minimized preview", renderer: renderer)
                    preview.window?.deminiaturize(nil)
                }
                app.menuBar?.onTitleBar?()
                preview.window?.performClose(nil)
                try await wait(app)
                try require(app.state.region == nil && app.preview == nil, "Closing the preview did not stop capture.")
                let closed = await renderer.statistics()
                try await Task.sleep(for: .milliseconds(200))
                let stopped = await renderer.statistics()
                try require(closed.received == stopped.received, "Frames kept arriving after preview close.")
                print("PASS: display \(region.display.displayID), scale \(region.pixelScale), \(resumed.size), \(resumed.received) frames, \(resumed.presented) presentations; selection/Escape, shareable window, title-bar toggle, resize, pause/resume, cursor updates, close")

                for pauseBeforeStop in [false, true] {
                    app.menuBar?.onSelect?()
                    try await wait(app)
                    try select(on: screen)
                    try await wait(app)
                    guard let stopPreview = app.preview, let stopRenderer = stopPreview.preview.renderer else {
                        throw CaptureError.message("Stop Sharing check did not start capture.")
                    }
                    if pauseBeforeStop {
                        app.menuBar?.onPause?()
                        try await wait(app)
                        try require(app.state.isPaused, "Stop Sharing check did not pause capture.")
                    }
                    app.menuBar?.onStop?()
                    try require(app.preview == nil && stopPreview.window?.isVisible == false,
                                "Stop Sharing did not immediately close the preview.")
                    try await wait(app)
                    try require(app.state.region == nil && !app.state.isSelecting, "Stop Sharing did not return to idle.")
                    let stopped = await stopRenderer.statistics()
                    try await Task.sleep(for: .milliseconds(200))
                    let later = await stopRenderer.statistics()
                    try require(later.received == stopped.received, "Frames kept arriving after Stop Sharing.")
                }
                print("PASS: Stop Sharing closes active and paused previews with hidden title bars")

                // These notifications are process-local; the test does not put the Mac to sleep or switch users.
                for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                             NSWorkspace.sessionDidResignActiveNotification] {
                    app.menuBar?.onSelect?()
                    try await wait(app)
                    try select(on: screen)
                    try await wait(app)
                    try require(app.state.region != nil, "Session-stop check did not start capture.")
                    try require(app.preview?.window?.titleVisibility == .hidden,
                                "New preview did not retain the hidden title-bar preference.")
                    NSWorkspace.shared.notificationCenter.post(name: name, object: NSWorkspace.shared)
                    try await wait(app)
                    try require(app.state.region == nil && app.preview == nil, "Sleep/session change did not end capture.")
                }
                print("PASS: sleep and session-switch notifications end capture")
                app.menuBar?.onTitleBar?()
            }
            if profiling { try await ResourceMeasurement.measure("after close") }
            print("Capture smoke check completed.")
        } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
        NSApp.terminate(nil)
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

    private static func select(on screen: NSScreen) throws {
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
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CaptureError.message(message) }
    }
}
