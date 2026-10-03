import AppKit

// Plain assertions keep these checks runnable with Command Line Tools alone (no XCTest/Xcode).
@main
enum CoordinateChecks {
    static func main() {
        // Same local selection on displays above, below, left, and right of the main display.
        for origin in [CGPoint.zero, CGPoint(x: -1920, y: -240), CGPoint(x: 1920, y: 300),
                       CGPoint(x: 0, y: 1080), CGPoint(x: 0, y: -1080)] {
            let screen = CGRect(origin: origin, size: CGSize(width: 1920, height: 1080))
            let rect = CGRect(x: origin.x + 100, y: origin.y + 200, width: 640, height: 360)
            for scale in [CGFloat(1), 2] {
                let crop = CoordinateConverter.captureRect(globalAppKitRect: rect, screenFrame: screen, pixelScale: scale)
                assert(crop == CGRect(x: 100, y: 520, width: 640, height: 360))
                assert(crop!.width * scale == (scale == 1 ? 640 : 1280))
            }
        }
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        assert(CoordinateConverter.isValidCaptureRect(bounds, displaySize: bounds.size, pixelScale: 2))
        for rect in [CGRect.zero, CGRect(x: -1, y: 0, width: 20, height: 20),
                     CGRect(x: 1910, y: 0, width: 20, height: 20),
                     CGRect(x: 0, y: 1070, width: 20, height: 20),
                     CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20),
                     CGRect(x: 100, y: 100, width: -20, height: 20)] {
            assert(!CoordinateConverter.isValidCaptureRect(rect, displaySize: bounds.size, pixelScale: 1))
        }
        for scale in [CGFloat.zero, -1, .nan, .infinity, .greatestFiniteMagnitude] {
            assert(!CoordinateConverter.isValidCaptureRect(bounds, displaySize: bounds.size, pixelScale: scale))
        }
        let drag = CoordinateConverter.selectionRect(from: CGPoint(x: 600, y: 400),
                                                      to: CGPoint(x: -800, y: 1500), in: bounds)
        assert(drag == CGRect(x: 0, y: 400, width: 600, height: 680))
        assert(CoordinateConverter.captureRect(globalAppKitRect: drag, screenFrame: bounds, pixelScale: 2)
               == CGRect(x: 0, y: 0, width: 600, height: 680))
        assert(CoordinateConverter.captureRect(globalAppKitRect: CGRect(x: 0, y: 0, width: 19, height: 30),
                                               screenFrame: bounds, pixelScale: 2) == nil)
        assert(CoordinateConverter.captureRect(globalAppKitRect: bounds, screenFrame: bounds, pixelScale: 0) == nil)
        assert(CoordinateConverter.captureRect(globalAppKitRect: CGRect(x: 10.2, y: 30.2, width: 20.1, height: 20.1),
                                               screenFrame: bounds, pixelScale: 2)
               == CGRect(x: 10, y: 1029.5, width: 20.5, height: 20.5))
        let landscape = FrameRenderer.viewport(imageSize: CGSize(width: 640, height: 360), drawableSize: CGSize(width: 400, height: 400))
        assert(landscape.originX == 0 && landscape.originY == 87.5 && landscape.width == 400 && landscape.height == 225)
        let portrait = FrameRenderer.viewport(imageSize: CGSize(width: 360, height: 640), drawableSize: CGSize(width: 800, height: 400))
        assert(portrait.originX == 287.5 && portrait.originY == 0 && portrait.width == 225 && portrait.height == 400)
        print("PASS: coordinate origins, Retina pixel alignment, drag clamping, fail-closed crop validation, letterboxing")
    }
}
