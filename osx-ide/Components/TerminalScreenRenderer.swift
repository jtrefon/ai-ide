import AppKit

/// Renders a TerminalScreenBuffer to an NSTextView
@MainActor
class TerminalScreenRenderer {
    private weak var textView: NSTextView?
    private let fontManager: (CGFloat, String) -> NSFont
    
    init(textView: NSTextView?, fontResolver: @escaping (CGFloat, String) -> NSFont) {
        self.textView = textView
        self.fontManager = fontResolver
    }
    
    /// Render the screen buffer to the text view
    func render(_ buffer: TerminalScreenBuffer, fontSize: CGFloat, fontFamily: String) {
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }
        
        let result = NSMutableAttributedString()
        
        // Only render rows that have content (up to and including cursor row)
        let maxRow = min(buffer.cursorRow + 1, buffer.rows)
        
        for row in 0..<maxRow {
            // Find the last non-space character in this row
            var lastNonSpaceCol = -1
            for col in (0..<buffer.columns).reversed() {
                if buffer.grid[row][col].character != " " {
                    lastNonSpaceCol = col
                    break
                }
            }

            // Render only up to the last non-space character (or cursor column if on cursor row)
            let renderUpTo: Int
            if row == buffer.cursorRow {
                // cursorColumn points *after* the last written character in many cases.
                // Rendering up to cursorColumn can introduce a trailing space.
                renderUpTo = max(lastNonSpaceCol, buffer.cursorColumn - 1)
            } else {
                renderUpTo = lastNonSpaceCol
            }

            guard renderUpTo >= 0 else {
                if row < maxRow - 1 {
                    result.append(NSAttributedString(string: "\n"))
                }
                continue
            }

            for col in 0...renderUpTo {
                let cell = buffer.grid[row][col]
                let attrs = attributesForCell(cell, fontSize: fontSize, fontFamily: fontFamily)
                result.append(NSAttributedString(string: String(cell.character), attributes: attrs))
            }
            
            // Add newline except for last row
            if row < maxRow - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: result)
        textStorage.endEditing()
    }
    
    /// Calculate the text position in the rendered string from buffer cursor coordinates
    /// The rendered string has variable-length rows (trimmed trailing spaces)
    /// We need to count characters up to the cursor position
    func cursorTextPosition(in buffer: TerminalScreenBuffer) -> Int {
        var position = 0
        
        // Count all characters in rows before the cursor row
        for row in 0..<buffer.cursorRow {
            // Find the last non-space character in this row
            var lastNonSpaceCol = -1
            for col in (0..<buffer.columns).reversed() {
                if buffer.grid[row][col].character != " " {
                    lastNonSpaceCol = col
                    break
                }
            }
            // Add characters in this row + newline
            position += lastNonSpaceCol + 2  // +1 for 0-indexed, +1 for newline
        }
        
        // Add the cursor column position in the current row
        position += buffer.cursorColumn
        
        return position
    }
    
    private func attributesForCell(_ cell: TerminalCell, fontSize: CGFloat, fontFamily: String) -> [NSAttributedString.Key: Any] {
        var font = fontManager(fontSize, fontFamily)
        if cell.isBold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: cell.foregroundColor,
            .backgroundColor: cell.backgroundColor
        ]
        
        if cell.isUnderlined {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        
        return attrs
    }
}
