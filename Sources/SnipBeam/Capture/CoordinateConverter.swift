import AppKit
import ScreenCaptureKit

enum CoordinateConverter {
    static let minimumSelectionSize: CGFloat = 20

    // Fail closed before configuring SCK: an empty/invalid crop must never fall back to a whole display.
    static func isValidCaptureRect(_ rect: CGRect, displaySize: CGSize, pixelScale: CGFloat) -> Bool {
        guard [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
               displaySize.width, displaySize.height, pixelScale].allSatisfy({ $0.isFinite }),
              pixelScale > 0, displaySize.width > 0, displaySize.height > 0,
              rect.size.width >= minimumSelectionSize, rect.size.height >= minimumSelectionSize,
              CGRect(origin: .zero, size: displaySize).contains(rect),
              let width = Int(exactly: (rect.width * pixelScale).rounded()),
              let height = Int(exactly: (rect.height * pixelScale).rounded()) else { return false }
        return width > 0 && height > 0
    }

    @MainActor
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    // Overlay-local coordinates are unflipped AppKit points. Clamp the drag to its starting screen.
    static func selectionRect(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                    y: min(max(point.y, bounds.minY), bounds.maxY))
        }
        let a = clamp(start), b = clamp(end)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // Global AppKit uses a bottom-left origin. SCK sourceRect uses a display-local top-left origin.
    // Subtract this screen's own origin; never flip against the main display's height.
    static func captureRect(globalAppKitRect rect: CGRect, screenFrame: CGRect, pixelScale: CGFloat) -> CGRect? {
        guard pixelScale.isFinite, pixelScale > 0,
              rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite else { return nil }
        let clipped = rect.standardized.intersection(screenFrame)
        guard !clipped.isNull, clipped.width >= minimumSelectionSize,
              clipped.height >= minimumSelectionSize else { return nil }
        let local = CGRect(x: clipped.minX - screenFrame.minX, y: screenFrame.maxY - clipped.maxY,
                           width: clipped.width, height: clipped.height)
        // Align outwards to pixel edges, preserving all the pixels selected by the user.
        let x = floor(local.minX * pixelScale) / pixelScale
        let y = floor(local.minY * pixelScale) / pixelScale
        let right = ceil(local.maxX * pixelScale) / pixelScale
        let bottom = ceil(local.maxY * pixelScale) / pixelScale
        return CGRect(x: x, y: y, width: right - x, height: bottom - y)
            .intersection(CGRect(origin: .zero, size: screenFrame.size))
    }

    @MainActor
    static func region(localSelection: CGRect, screen: NSScreen, display: SCDisplay) -> CaptureRegion? {
        guard displayID(for: screen) == display.displayID else { return nil }
        let scale = CGFloat(SCContentFilter(display: display, excludingWindows: []).pointPixelScale)
        let global = localSelection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        guard let rect = captureRect(globalAppKitRect: global, screenFrame: screen.frame, pixelScale: scale) else { return nil }
        return CaptureRegion(display: display, rectInDisplayPoints: rect, pixelScale: scale)
    }
}
