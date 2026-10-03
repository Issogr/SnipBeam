import AppKit

// Original vector artwork; regenerate with the native iconutil tool during packaging.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.25, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 20, y: 20, width: 472, height: 472),
                     xRadius: 104, yRadius: 104).fill()
        NSColor(calibratedRed: 0.28, green: 0.9, blue: 0.75, alpha: 1).setStroke()
        let frame = NSBezierPath(roundedRect: NSRect(x: 114, y: 148, width: 284, height: 216),
                                 xRadius: 16, yRadius: 16)
        frame.lineWidth = 22
        frame.stroke()
        NSColor.white.setStroke()
        let corners = NSBezierPath()
        for (x, y, dx, dy) in [(82.0, 394.0, 64.0, -64.0), (430, 394, -64, -64),
                               (82, 118, 64, 64), (430, 118, -64, 64)] {
            corners.move(to: NSPoint(x: x + dx, y: y))
            corners.line(to: NSPoint(x: x, y: y))
            corners.line(to: NSPoint(x: x, y: y + dy))
        }
        corners.lineWidth = 16
        corners.lineCapStyle = .round
        corners.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
