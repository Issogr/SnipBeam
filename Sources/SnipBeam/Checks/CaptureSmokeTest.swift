import AppKit
import ScreenCaptureKit
import Security

// Opt-in check of the real app controls: packaged executable --smoke-test.
// Everything stays in memory; no screenshots or frames are written to disk.
@MainActor
enum CaptureSmokeTest {
    private static let fixtureID = "com.example.SnipBeam.CaptureFixture"

    static func run(appDelegate app: AppDelegate) async {
        setbuf(stdout, nil)
        let profiling = CommandLine.arguments.contains("--performance-test")
        let timeout = CaptureCheckSettings.timeout(profiling: profiling, displayCount: NSScreen.screens.count)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            UserDefaults.standard.removePersistentDomain(forName: CaptureCheckSettings.preferencesDomain)
            print("FAIL: capture check timed out")
            exit(1)
        }
        do {
            defer {
                app.preferences.removePersistentDomain(forName: CaptureCheckSettings.preferencesDomain)
            }
            guard let task = SecTaskCreateFromSelf(nil) else { throw CaptureError.message("Could not inspect code-signing entitlements.") }
            try require(SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool == true,
                        "The packaged app is not sandboxed.")
            if let path = ProcessInfo.processInfo.environment["SNIPBEAM_SANDBOX_PROBE"] {
                let result = access(path, R_OK)
                try require(result == -1 && (errno == EPERM || errno == EACCES), "Sandbox allowed access to the external test fixture.")
                print("PASS: sandbox denies access to the external test fixture")
            }
            try require(CGPreflightScreenCaptureAccess(), "Grant SnipBeam Screen Recording permission before running the smoke check.")
            _ = try await fixtureApplication()
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

                var startup: CheckedContinuation<Void, Never>?
                app.beforeCaptureStart = { await withCheckedContinuation { startup = $0 } }
                app.menuBar?.onSelect?()
                try await wait(app)
                try select(on: screen)
                while startup == nil { try await Task.sleep(for: .milliseconds(1)) }
                guard app.busy, let startingPreview = app.preview, let startingRenderer = startingPreview.preview.renderer else {
                    throw CaptureError.message("The cancellation check did not hold an in-flight start.")
                }
                startingPreview.close()
                startup?.resume()
                app.beforeCaptureStart = nil
                try await wait(app)
                try await Task.sleep(for: .milliseconds(200))
                let cancelled = await startingRenderer.statistics()
                try require(app.state.region == nil && !app.state.isSelecting && app.preview == nil &&
                            !app.busy && startingPreview.window?.isVisible == false && cancelled.received == 0,
                            "Closing during startup revived capture or delivered frames.")
                print("PASS: closing an in-flight start stays idle without delivering frames")

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
                await renderer.checkFrames(matching: { containsFixture($0) })
                try await expectFixture(true, renderer: renderer)
                app.menuBar?.onHiddenApps?()
                guard let hiddenApps = app.hiddenApps, let hiddenWindow = hiddenApps.window else {
                    throw CaptureError.message("Hidden Apps did not open a window.")
                }
                app.menuBar?.onHiddenApps?()
                try require(app.hiddenApps === hiddenApps && hiddenWindow.isVisible, "Hidden Apps did not reuse its window.")
                let appCheckboxes = hiddenAppCheckboxes(in: hiddenWindow)
                try require(!appCheckboxes.contains { $0.identifier?.rawValue == Bundle.main.bundleIdentifier },
                            "SnipBeam should not be an optional exclusion.")
                guard var appCheckbox = appCheckboxes.first(where: { $0.identifier?.rawValue == fixtureID }) else {
                    throw CaptureError.message("The visual fixture is missing from Hidden Apps. Run scripts/live-check.py.")
                }
                hiddenWindow.contentView?.layoutSubtreeIfNeeded()
                try require(appCheckbox.frame.height > 0 && appCheckbox.frame.width <= hiddenWindow.contentView!.bounds.width,
                            "Hidden Apps checkboxes did not lay out inside the window.")
                try require(appCheckbox.state == .off, "The fixture was unexpectedly hidden before the pixel check.")
                let beforeHide = await renderer.statistics().received
                appCheckbox.performClick(nil)
                try require(app.busy && !appCheckbox.isEnabled, "Hidden Apps controls were not disabled during the filter update.")
                try await wait(app)
                try require((app.preferences.stringArray(forKey: "hiddenAppBundleIDs") ?? []).contains(fixtureID) &&
                            appCheckbox.isEnabled && app.preview === preview && app.state.region != nil,
                            "Changing hidden apps did not save the selection and keep the current capture.")
                try await expectFixture(false, renderer: renderer, after: beforeHide)
                let previousFixture = try await fixtureApplication()
                await renderer.checkFrames(matching: { containsFixture($0) })
                let beforeRelaunch = await renderer.statistics().received
                print("FIXTURE: relaunch")
                _ = try await fixtureApplication(replacing: previousFixture.processID)
                try await wait(app)
                try require(app.preview === preview && app.state.region != nil, "Relaunching the hidden fixture ended capture.")
                try await expectFixture(false, renderer: renderer, after: beforeRelaunch)
                try require(await renderer.statistics().matches == 0, "Hidden fixture pixels leaked during relaunch.")
                guard let reloadedCheckbox = hiddenAppCheckboxes(in: hiddenWindow).first(where: { $0.identifier?.rawValue == fixtureID }) else {
                    throw CaptureError.message("The relaunched fixture disappeared from Hidden Apps.")
                }
                appCheckbox = reloadedCheckbox
                print("PASS: fixture pixels disappear when hidden and stay absent throughout relaunch")
                let window = preview.window!
                let windowNumber = window.windowNumber
                let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
                app.menuBar?.onTitleBar?()
                try require(app.preferences.bool(forKey: "hidesTitleBar") &&
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
                appCheckbox.performClick(nil)
                try await wait(app)
                try require(!(app.preferences.stringArray(forKey: "hiddenAppBundleIDs") ?? []).contains(fixtureID) &&
                            app.state.isPaused && app.preview === preview,
                            "Changing hidden apps while paused did not preserve the paused capture.")
                hiddenApps.close()
                app.menuBar?.onHiddenApps?()
                try require(hiddenAppCheckboxes(in: hiddenWindow).first(where: { $0.identifier?.rawValue == fixtureID })?.state == .off,
                            "Reopening Hidden Apps lost the checkbox selection.")
                hiddenApps.close()
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
                try require(!app.preferences.bool(forKey: "hidesTitleBar") &&
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
                try await expectFixture(true, renderer: renderer, after: paused.received)
                await renderer.checkFrames(matching: nil)
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
                print("PASS: display \(region.display.displayID), scale \(region.pixelScale), \(resumed.size), \(resumed.received) frames, \(resumed.presented) presentations; selection/Escape, shareable window, hidden-app selections, title-bar toggle, resize, pause/resume, cursor updates, close")

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

    private static func fixtureApplication(replacing oldPID: pid_t? = nil) async throws -> SCRunningApplication {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        repeat {
            let content = try await ScreenCaptureManager.content()
            if let application = content.applications.first(where: { $0.bundleIdentifier == fixtureID && $0.processID != oldPID }),
               content.windows.contains(where: { $0.owningApplication?.processID == application.processID && $0.isOnScreen }) {
                return application
            }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        throw CaptureError.message("The visual fixture did not launch. Run python3 -B scripts/live-check.py.")
    }

    private static func expectFixture(_ visible: Bool, renderer: FrameRenderer, after received: Int = -1) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat {
            let stats = await renderer.statistics()
            if stats.received > received && stats.latestMatches == visible { return }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        throw CaptureError.message("Fixture pixels were not \(visible ? "visible" : "hidden") in a fresh captured frame.")
    }

    nonisolated private static func containsFixture(_ pixels: CVPixelBuffer) -> Bool {
        guard CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return false }
        let row = base.advanced(by: CVPixelBufferGetBytesPerRow(pixels) * (CVPixelBufferGetHeight(pixels) / 2))
            .assumingMemoryBound(to: UInt8.self)
        let left = (CVPixelBufferGetWidth(pixels) / 4) * 4
        let right = (CVPixelBufferGetWidth(pixels) * 3 / 4) * 4
        return row[left] > 220 && row[left + 1] < 30 && row[left + 2] > 220 &&
               row[right] < 30 && row[right + 1] > 220 && row[right + 2] > 220
    }

    private static func hiddenAppCheckboxes(in window: NSWindow) -> [NSButton] {
        let scroll = window.contentView?.subviews.compactMap { $0 as? NSScrollView }.first
        let list = scroll?.documentView as? NSStackView
        return list?.arrangedSubviews.compactMap { $0 as? NSButton } ?? []
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
