import AppKit

@MainActor
final class NativeTerminalTextView: NSTextView {
    weak var inputDelegate: NativeTerminalEmbedder?
    private var cursorTimer: Timer?
    private var cursorVisible = true
    private var cursorBlinkRate: TimeInterval = 0.5

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let characters = event.characters {
            inputDelegate?.forwardTerminalInput(characters)
        }
    }

    override func doCommand(by selector: Selector) {
        guard let inputDelegate else { return }
        _ = inputDelegate.handleTerminalCommand(selector)
    }

    // MARK: - Block Cursor Support

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            startCursorBlinking()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        stopCursorBlinking()
        return result
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // Draw a block cursor instead of the default vertical line
        guard cursorVisible else { return }

        // DEBUG: Log cursor drawing
        let cursorPosition = selectedRange().location
        print("[DEBUG TerminalTextView] drawInsertionPoint - selectedRange.location: \(cursorPosition), rect: \(rect)")

        // Calculate block cursor dimensions based on font
        let font = self.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let charWidth = font.maximumAdvancement.width
        let blockWidth = max(charWidth, 8)

        let blockRect = NSRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: blockWidth,
            height: rect.height
        )

        // Draw the block cursor with green color
        NSColor.green.setFill()
        let path = NSBezierPath(rect: blockRect)
        path.fill()

        // Draw the character underneath in black for visibility
        if let textStorage = textStorage, cursorPosition < textStorage.length {
            let text = textStorage.string as NSString
            if cursorPosition < text.length {
                let char = text.substring(with: NSRange(location: cursorPosition, length: 1))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.black
                ]
                char.draw(in: blockRect, withAttributes: attrs)
            }
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
    }

    private func startCursorBlinking() {
        stopCursorBlinking()
        cursorVisible = true
        cursorTimer = Timer.scheduledTimer(withTimeInterval: cursorBlinkRate, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.toggleCursor()
            }
        }
    }

    private func stopCursorBlinking() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        cursorVisible = true
    }

    private func toggleCursor() {
        cursorVisible.toggle()
        needsDisplay = true
    }

    // Ensure cursor is drawn even when not blinking
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
}
