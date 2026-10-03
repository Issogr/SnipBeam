import CoreMedia
import ScreenCaptureKit

@MainActor
final class ScreenCaptureManager: NSObject, SCStreamDelegate {
    private var stream: SCStream?
    private var receiver: FrameReceiver?
    private var isRunning = false
    var onError: ((Error) -> Void)?

    static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    }

    func start(region: CaptureRegion, content: SCShareableContent,
               renderer: FrameRenderer, showsCursor: Bool) async throws {
        guard stream == nil else { throw CaptureError.message("Capture is already running. Close the preview and retry.") }
        guard CGDisplayIsActive(region.display.displayID) != 0,
              region.rectInDisplayPoints.width >= CoordinateConverter.minimumSelectionSize,
              region.rectInDisplayPoints.height >= CoordinateConverter.minimumSelectionSize else {
            throw CaptureError.message("The selected display or region is no longer available. Select Region again.")
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        guard !ownApps.isEmpty else {
            throw CaptureError.message("SnipBeam could not exclude its own windows. Quit and reopen the app, then retry.")
        }
        let filter = SCContentFilter(display: region.display, excludingApplications: ownApps, exceptingWindows: [])
        let receiver = FrameReceiver(renderer: renderer)
        let stream = SCStream(filter: filter, configuration: configuration(region, showsCursor: showsCursor), delegate: self)
        try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: renderer.queue)
        self.receiver = receiver
        self.stream = stream
        do {
            try await stream.startCapture()
            guard self.stream === stream else {
                throw CaptureError.message("The capture stream stopped while starting. Select Region to retry.")
            }
            isRunning = true
        } catch {
            receiver.setEnabled(false)
            self.stream = nil
            self.receiver = nil
            throw error
        }
    }

    func stop() async throws {
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
    }

    func resume() async throws {
        guard let stream, !isRunning else {
            throw CaptureError.message("The paused stream is no longer available. Select Region again.")
        }
        receiver?.setEnabled(true)
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

    private func configuration(_ region: CaptureRegion, showsCursor: Bool) -> SCStreamConfiguration {
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
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.isRunning = false
            self.receiver?.setEnabled(false)
            self.receiver = nil
            self.onError?(error)
        }
    }
}
