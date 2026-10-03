import ScreenCaptureKit

struct CaptureRegion {
    let display: SCDisplay
    // Top-left origin, local to this display, in logical points.
    let rectInDisplayPoints: CGRect
    let pixelScale: CGFloat

    var pixelWidth: Int { max(1, Int((rectInDisplayPoints.width * pixelScale).rounded())) }
    var pixelHeight: Int { max(1, Int((rectInDisplayPoints.height * pixelScale).rounded())) }
}

enum CaptureState {
    case idle
    case selecting
    case capturing(CaptureRegion)
    case paused(CaptureRegion)

    var region: CaptureRegion? {
        switch self {
        case .capturing(let region), .paused(let region): return region
        case .idle, .selecting: return nil
        }
    }
    var isPaused: Bool { if case .paused = self { return true }; return false }
    var isSelecting: Bool { if case .selecting = self { return true }; return false }
}

enum CaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}
