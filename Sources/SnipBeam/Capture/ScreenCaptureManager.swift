import AppKit
import CoreMedia
import ScreenCaptureKit

@MainActor
final class ScreenCaptureManager: NSObject, SCStreamDelegate {
    // The Dock process also owns the Command-Tab app switcher.
    static let dockBundleID = "com.apple.dock"

    // Only pointer equality crosses queues. Retaining the object prevents address reuse before the check.
    private struct StreamIdentity: @unchecked Sendable {
        let stream: SCStream
    }

    private var stream: SCStream?
    private var receiver: FrameReceiver?
    private var isRunning = false
    private var filterRevision = 0
    private var installedFilterRevision = 0
    private var pendingApplications: [pid_t: NSRunningApplication] = [:]
    var onError: ((Error) -> Void)?

    static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    }

    func start(region: CaptureRegion,
                renderer: FrameRenderer, showsCursor: Bool, hiddenAppBundleIDs: Set<String>) async throws {
        guard stream == nil else { throw CaptureError.message("Capture is already running. Close the preview and retry.") }
        let (filter, revision) = try await refreshedFilter(region: region, bundleIDs: hiddenAppBundleIDs)
        try Task.checkCancellation()
        let receiver = FrameReceiver(renderer: renderer)
        let stream = try SCStream(filter: filter, configuration: configuration(region, showsCursor: showsCursor), delegate: self)
        try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: renderer.queue)
        self.receiver = receiver
        self.stream = stream
        installedFilterRevision = revision
        do {
            try await startStream()
        } catch {
            receiver.setEnabled(false)
            self.stream = nil
            self.receiver = nil
            throw error
        }
    }

    func stop() async throws {
        pendingApplications.removeAll()
        guard let stream else { return }
        self.stream = nil
        receiver?.setEnabled(false)
        defer {
            if let receiver { try? stream.removeStreamOutput(receiver, type: .screen) }
            receiver = nil
            isRunning = false
        }
        if isRunning { try await stream.stopCapture() }
    }

    func pause() async throws {
        guard let stream, isRunning else { return }
        receiver?.setEnabled(false)
        try await stream.stopCapture()
        isRunning = false
        await receiver?.drain()
    }

    func resume(region: CaptureRegion, hiddenAppBundleIDs: Set<String>) async throws {
        try validate(region)
        guard stream != nil, !isRunning else {
            throw CaptureError.message("The paused stream is no longer available. Select Region again.")
        }
        try await updateHiddenApps(hiddenAppBundleIDs, region: region)
        try await startStream()
    }

    private func startStream() async throws {
        try Task.checkCancellation()
        guard let stream else { throw CaptureError.message("Capture has stopped. Select Region again.") }
        receiver?.setEnabled(installedFilterRevision == filterRevision)
        do {
            try await stream.startCapture()
            guard self.stream === stream else {
                throw CaptureError.message("The capture stream stopped while resuming. Select Region again.")
            }
            isRunning = true
        } catch {
            receiver?.setEnabled(false)
            throw error
        }
    }

    func updateCursor(_ showsCursor: Bool, region: CaptureRegion) async throws {
        guard let stream else { throw CaptureError.message("Capture has stopped. Select Region again.") }
        try await stream.updateConfiguration(configuration(region, showsCursor: showsCursor))
    }

    func updateHiddenApps(_ bundleIDs: Set<String>, region: CaptureRegion) async throws {
        guard let stream else { throw CaptureError.message("Capture has stopped. Select Region again.") }
        suspendFrameDelivery()
        let wasRunning = isRunning
        if wasRunning { try await pause() }
        let (filter, revision) = try await refreshedFilter(region: region, bundleIDs: bundleIDs)
        try Task.checkCancellation()
        guard self.stream === stream else { throw CaptureError.message("Capture stopped while updating hidden apps.") }
        try validate(region)
        try await stream.updateContentFilter(filter)
        try Task.checkCancellation()
        installedFilterRevision = revision
        if wasRunning { try await startStream() }
    }

    func suspendFrameDelivery(for application: NSRunningApplication? = nil) {
        filterRevision += 1
        receiver?.setEnabled(false)
        pendingApplications = pendingApplications.filter { !$0.value.isTerminated }
        if let application, !application.isTerminated {
            pendingApplications[application.processIdentifier] = application
        }
    }

    private func refreshedFilter(region: CaptureRegion, bundleIDs: Set<String>) async throws -> (SCContentFilter, Int) {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat {
            try Task.checkCancellation()
            let revision = filterRevision
            let content = try await Self.content()
            try Task.checkCancellation()
            let expected = (NSWorkspace.shared.runningApplications + Array(pendingApplications.values)).filter {
                !$0.isTerminated && ($0.bundleIdentifier == Self.dockBundleID || bundleIDs.contains($0.bundleIdentifier ?? ""))
            }
            if revision == filterRevision && expected.allSatisfy({ app in
                app.isFinishedLaunching && content.applications.contains { $0.processID == app.processIdentifier }
            }) {
                let filter = try contentFilter(region: region, content: content, hiddenAppBundleIDs: bundleIDs)
                pendingApplications.removeAll()
                return (filter, revision)
            }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        throw CaptureError.message("A hidden app could not be excluded safely. Wait for it to finish launching, then select the region again.")
    }

    private func contentFilter(region: CaptureRegion, content: SCShareableContent,
                               hiddenAppBundleIDs: Set<String>) throws -> SCContentFilter {
        guard let display = content.displays.first(where: { $0.displayID == region.display.displayID }),
              display.frame == region.display.frame else {
            throw CaptureError.message("The selected display or region is no longer available. Select Region again.")
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard content.applications.contains(where: { $0.processID == ownPID }) else {
            throw CaptureError.message("SnipBeam could not exclude its own windows. Quit and reopen the app, then retry.")
        }
        let excluded = content.applications.filter {
            $0.processID == ownPID || $0.bundleIdentifier == Self.dockBundleID || hiddenAppBundleIDs.contains($0.bundleIdentifier)
        }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        guard CGFloat(filter.pointPixelScale) == region.pixelScale else {
            throw CaptureError.message("The display scale changed. Select Region again.")
        }
        return filter
    }

    private func validate(_ region: CaptureRegion) throws {
        guard CGDisplayIsActive(region.display.displayID) != 0,
              CGDisplayBounds(region.display.displayID) == region.display.frame,
              CoordinateConverter.isValidCaptureRect(region.rectInDisplayPoints, displaySize: region.display.frame.size,
                                                       pixelScale: region.pixelScale) else {
            throw CaptureError.message("The selected display or crop is no longer valid. Select Region again.")
        }
    }

    private func configuration(_ region: CaptureRegion, showsCursor: Bool) throws -> SCStreamConfiguration {
        try validate(region)
        let config = SCStreamConfiguration()
        config.sourceRect = region.rectInDisplayPoints
        config.width = region.pixelWidth
        config.height = region.pixelHeight
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.showsCursor = showsCursor
        config.capturesAudio = false
        return config
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let stopped = StreamIdentity(stream: stream)
        Task { @MainActor [weak self] in
            guard let self, self.stream === stopped.stream else { return }
            self.stream = nil
            self.isRunning = false
            self.receiver?.setEnabled(false)
            self.receiver = nil
            self.onError?(error)
        }
    }
}
