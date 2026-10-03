import AppKit

final class SelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    private var instruction = "Drag to select a region on this display · Escape to cancel"

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = CoordinateConverter.selectionRect(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        start = nil
        guard let selection, selection.width >= CoordinateConverter.minimumSelectionSize,
              selection.height >= CoordinateConverter.minimumSelectionSize else {
            instruction = "Select at least 20 × 20 points · Drag again or press Escape"
            NSSound.beep()
            needsDisplay = true
            return
        }
        onSelection?(selection)
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let selection { dim.appendRect(selection) }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.3).setFill()
        dim.fill()
        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
        }
        let size = selection.map { "\n\(Int($0.width)) × \(Int($0.height)) points" } ?? ""
        let text = instruction + size
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (text as NSString).draw(in: NSRect(x: 20, y: bounds.height - 100, width: bounds.width - 40, height: 70),
                               withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .medium),
                                                .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
    }
}
