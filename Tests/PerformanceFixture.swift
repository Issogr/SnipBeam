import AppKit
import QuartzCore

// A separate process supplies repeatable animated content; SnipBeam excludes its own windows.
@main
final class PerformanceFixture: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = PerformanceFixture()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        windows = NSScreen.screens.map { screen in
            let frame = CGRect(x: screen.frame.minX + 80, y: screen.frame.minY + 80,
                               width: min(640, screen.frame.width - 80), height: min(360, screen.frame.height - 80))
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "SnipBeam performance fixture"
            window.level = .floating
            let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
            view.wantsLayer = true
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = NSColor.systemBlue.cgColor
            animation.toValue = NSColor.systemGreen.cgColor
            animation.duration = 1
            animation.autoreverses = true
            animation.repeatCount = .infinity
            view.layer?.add(animation, forKey: "color")
            for (x, color) in [(0.1, NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)),
                               (0.6, NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))] {
                let marker = CALayer()
                marker.frame = CGRect(x: frame.width * x, y: frame.height * 0.25,
                                      width: frame.width * 0.3, height: frame.height * 0.5)
                marker.backgroundColor = color.cgColor
                view.layer?.addSublayer(marker)
            }
            window.contentView = view
            window.orderFrontRegardless()
            return window
        }
    }
}
