import AppKit
import QuartzCore

// A separate process supplies repeatable animated content; SnipBeam excludes its own windows.
@main
enum PerformanceFixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let windows = NSScreen.screens.map { screen in
            let frame = CGRect(x: screen.frame.minX + 80, y: screen.frame.minY + 80,
                               width: min(640, screen.frame.width - 80), height: min(360, screen.frame.height - 80))
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "SnipBeam performance fixture"
            let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
            view.wantsLayer = true
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = NSColor.systemBlue.cgColor
            animation.toValue = NSColor.systemGreen.cgColor
            animation.duration = 1
            animation.autoreverses = true
            animation.repeatCount = .infinity
            view.layer?.add(animation, forKey: "color")
            window.contentView = view
            window.orderFrontRegardless()
            return window
        }
        withExtendedLifetime(windows) { app.run() }
    }
}
