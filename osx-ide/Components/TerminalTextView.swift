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
        // Prevent clicking from changing the selection/cursor position
        // super.mouseDown(with: event) // Skip super to prevent selection change
    }

    override func keyDown(with event: NSEvent) {
        if let characters = event.characters {
            inputDelegate?.forwardTerminalInput(characters)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        // Only allow programmatic selection changes from the embedder
        // or effectively "lock" the external selection attempts
        if let _ = inputDelegate {
             super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag)
        }
    }

    override func doCommand(by selector: Selector) {
        guard let inputDelegate else { return }
        _ = inputDelegate.handleTerminalCommand(selector)
    }

    // MARK: - Block Cursor Support

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // Draw a block cursor instead of the default vertical line
        // We use the 'flag' parameter which indicates the system's blink state
        guard flag else { return }

        let cursorPosition = selectedRange().location

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
    
    // Disable the default cursor drawing
    override var shouldDrawInsertionPoint: Bool {
        return true
    }

    // Ensure cursor is drawn even when not blinking
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
}
