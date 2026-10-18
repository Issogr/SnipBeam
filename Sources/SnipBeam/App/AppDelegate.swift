import AppKit
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var menuBar: MenuBarController?
    private(set) var preview: PreviewWindowController?
    private(set) var hiddenApps: HiddenAppsWindowController?
    private var selection: SelectionWindowController?
    private let capture = ScreenCaptureManager()
    let preferences: UserDefaults
    // The smoke check holds startup here to exercise cancellation deterministically.
    var beforeCaptureStart: (() async -> Void)?
    private(set) var state: CaptureState = .idle { didSet { updateMenu() } }
    private var showsCursor: Bool {
        didSet {
            preferences.set(showsCursor, forKey: "showsCursor")
            updateMenu()
        }
    }
    private var hidesTitleBar: Bool {
        didSet {
            preferences.set(hidesTitleBar, forKey: "hidesTitleBar")
            preview?.setTitleBarHidden(hidesTitleBar)
            updateMenu()
        }
    }
    private var hiddenAppBundleIDs: Set<String>
    private var needsHiddenAppsUpdate = false
    private(set) var busy = false { didSet { updateMenu() } }
    private var operation: Task<Void, Never>?
    private var generation = 0

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        showsCursor = preferences.object(forKey: "showsCursor") as? Bool ?? true
        hidesTitleBar = preferences.bool(forKey: "hidesTitleBar")
        hiddenAppBundleIDs = Set(preferences.stringArray(forKey: "hiddenAppBundleIDs") ?? [])
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menuBar = MenuBarController()
        menuBar.onSelect = { [weak self] in self?.selectRegion() }
        menuBar.onPause = { [weak self] in self?.togglePause() }
        menuBar.onStop = { [weak self] in self?.stopCapture() }
        menuBar.onCursor = { [weak self] in self?.toggleCursor() }
        menuBar.onTitleBar = { [weak self] in self?.hidesTitleBar.toggle() }
        menuBar.onHiddenApps = { [weak self] in self?.showHiddenApps() }
        self.menuBar = menuBar
        capture.onError = { [weak self] error in self?.stopCapture(error: error) }
        updateMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sessionBecameInactive), name: name, object: nil)
        }
        for name in [NSWorkspace.willLaunchApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationsChanged(_:)), name: name, object: nil)
        }
        if CaptureCheckSettings.requested {
            Task { await CaptureSmokeTest.run(appDelegate: self) }
        }
    }

    private func selectRegion() {
        guard !busy, !state.isSelecting, ScreenRecordingPermission.ensureAccess() else { return }
        dismissPreview()
        state = .selecting
        perform { [self] in
            try await capture.stop()
            let content = try await ScreenCaptureManager.content()
            try Task.checkCancellation()
            let selection = SelectionWindowController()
            self.selection = selection
            try selection.begin(displays: content.displays) { [weak self] region in
                guard let self, self.state.isSelecting else { return }
                self.selection = nil
                guard let region else { self.state = .idle; return }
                self.startCapture(region)
            }
        }
    }

    private func startCapture(_ region: CaptureRegion) {
        perform { [self] in
            let preview = try PreviewWindowController(size: region.rectInDisplayPoints.size)
            preview.setTitleBarHidden(hidesTitleBar)
            guard let renderer = preview.preview.renderer else {
                throw CaptureError.message("The Metal preview is unavailable. Reopen SnipBeam to retry.")
            }
            self.preview = preview
            preview.onClose = { [weak self] in
                self?.preview = nil
                self?.stopCapture()
            }
            renderer.setFailureHandler { [weak self, weak renderer] message in
                Task { @MainActor in
                    guard let self, let renderer, self.preview?.preview.renderer === renderer else { return }
                    self.stopCapture(error: CaptureError.message(message))
                }
            }
            preview.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            await beforeCaptureStart?()
            try Task.checkCancellation()
            // Discover after opening the preview so our process is present in the exclusion list.
            try await capture.start(region: region, renderer: renderer, showsCursor: showsCursor,
                                    hiddenAppBundleIDs: hiddenAppBundleIDs)
            try Task.checkCancellation()
            state = .capturing(region)
        }
    }

    private func togglePause() {
        guard let region = state.region else { return }
        let resume = state.isPaused
        perform { [self] in
            if resume { try await capture.resume(region: region, hiddenAppBundleIDs: hiddenAppBundleIDs) }
            else { try await capture.pause() }
            try Task.checkCancellation()
            state = resume ? .capturing(region) : .paused(region)
            preview?.setPaused(!resume)
        }
    }

    private func toggleCursor() {
        let enabled = !showsCursor
        guard let region = state.region else { showsCursor = enabled; return }
        perform { [self] in
            try await capture.updateCursor(enabled, region: region)
            try Task.checkCancellation()
            showsCursor = enabled
        }
    }

    private func showHiddenApps() {
        guard !busy, !state.isSelecting else { return }
        if hiddenApps == nil {
            let controller = HiddenAppsWindowController()
            controller.onChange = { [weak self] id, hidden in
                guard let self, !self.busy, !self.state.isSelecting else { return }
                if hidden { self.hiddenAppBundleIDs.insert(id) } else { self.hiddenAppBundleIDs.remove(id) }
                self.preferences.set(self.hiddenAppBundleIDs.sorted(), forKey: "hiddenAppBundleIDs")
                self.requestHiddenAppsUpdate()
            }
            hiddenApps = controller
        }
        hiddenApps?.reloadApplications(hiddenBundleIDs: hiddenAppBundleIDs, enabled: true)
        hiddenApps?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func applicationsChanged(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let id = app.bundleIdentifier,
           id == ScreenCaptureManager.dockBundleID || hiddenAppBundleIDs.contains(id) {
            requestHiddenAppsUpdate(app)
        }
        hiddenApps?.reloadApplications(hiddenBundleIDs: hiddenAppBundleIDs, enabled: !busy && !state.isSelecting)
    }

    private func requestHiddenAppsUpdate(_ application: NSRunningApplication? = nil) {
        capture.suspendFrameDelivery(for: application)
        needsHiddenAppsUpdate = true
        if !busy { perform {} }
    }

    private func stopCapture(error: Error? = nil) {
        state = .idle
        selection?.cancel()
        selection = nil
        dismissPreview()
        perform(interrupt: true) { [self] in
            try await capture.stop()
            if let error { showError(error) }
        }
    }

    // Serialize control operations; close/display changes cancel and then drain an in-flight start.
    // This prevents an awaited startCapture from resurrecting a preview that the user just closed.
    private func perform(interrupt: Bool = false, _ work: @escaping @MainActor () async throws -> Void) {
        guard !busy || interrupt else { return }
        let previous = operation
        if interrupt { previous?.cancel() }
        generation += 1
        let ticket = generation
        busy = true
        operation = Task { [self] in
            if interrupt { await previous?.value }
            do {
                try Task.checkCancellation()
                try await work()
                // Coalesce app launches with user changes, using the same serialized capture operations.
                while needsHiddenAppsUpdate {
                    needsHiddenAppsUpdate = false
                    try Task.checkCancellation()
                    if let region = state.region {
                        try await capture.updateHiddenApps(hiddenAppBundleIDs, region: region)
                        try Task.checkCancellation()
                    }
                }
            } catch {
                if !Task.isCancelled {
                    try? await capture.stop()
                    state = .idle
                    selection?.cancel()
                    selection = nil
                    dismissPreview()
                    showError(error)
                }
            }
            guard generation == ticket else { return }
            busy = false
            operation = nil
        }
    }

    private func dismissPreview() {
        preview?.onClose = nil
        preview?.close()
        preview = nil
    }

    @objc private func displaysChanged() {
        guard state.isSelecting || state.region != nil else { return }
        // ponytail: any display rearrangement ends capture; reselect rather than risk sharing the wrong area.
        stopCapture(error: CaptureError.message("The display configuration changed. Choose Select Region again."))
    }

    @objc private func sessionBecameInactive() {
        guard state.isSelecting || state.region != nil else { return }
        // End the session rather than silently resuming capture after sleep or user switching.
        stopCapture()
    }

    private func updateMenu() {
        menuBar?.update(state: state, busy: busy, showsCursor: showsCursor, hidesTitleBar: hidesTitleBar)
        hiddenApps?.update(hiddenBundleIDs: hiddenAppBundleIDs, enabled: !busy && !state.isSelecting)
    }

    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "SnipBeam could not continue capture"
        alert.informativeText = error.localizedDescription + "\n\nChoose Select Region to retry. Check Screen Recording permission in System Settings if access was denied."
        alert.runModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        // ponytail: normal process exit releases the capture session without a nested run loop.
        operation?.cancel()
        selection?.cancel()
    }
}
