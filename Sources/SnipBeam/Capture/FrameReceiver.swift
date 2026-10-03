import CoreMedia
import ScreenCaptureKit

// enabled is only read/written on renderer.queue, the SCStream sample handler queue.
final class FrameReceiver: NSObject, SCStreamOutput, @unchecked Sendable {
    private let renderer: FrameRenderer
    private var enabled = true

    init(renderer: FrameRenderer) {
        self.renderer = renderer
    }

    func setEnabled(_ enabled: Bool) {
        renderer.queue.async { self.enabled = enabled }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard enabled, outputType == .screen, sampleBuffer.isValid,
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
