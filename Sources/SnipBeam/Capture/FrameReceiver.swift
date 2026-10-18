import CoreMedia
import ScreenCaptureKit
import os

// Close the gate immediately, even when capture callbacks are already queued.
final class FrameReceiver: NSObject, SCStreamOutput, @unchecked Sendable {
    private let renderer: FrameRenderer
    private let enabled = OSAllocatedUnfairLock(initialState: false)

    init(renderer: FrameRenderer) {
        self.renderer = renderer
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled.withLock { $0 = enabled }
    }

    func drain() async {
        await withCheckedContinuation { continuation in
            renderer.queue.async { continuation.resume() }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard enabled.withLock({ $0 }), outputType == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [NSDictionary],
              let status = attachments.first?[SCStreamFrameInfo.status.rawValue] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let pixels = sampleBuffer.imageBuffer,
              CVPixelBufferGetWidth(pixels) > 0, CVPixelBufferGetHeight(pixels) > 0,
              CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA else { return }
        renderer.receive(pixels)
    }
}
