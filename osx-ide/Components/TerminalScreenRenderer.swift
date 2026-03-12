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
        
        for row in 0..<buffer.rows {
            for col in 0..<buffer.columns {
                let cell = buffer.grid[row][col]
                let attrs = attributesForCell(cell, fontSize: fontSize, fontFamily: fontFamily)
                result.append(NSAttributedString(string: String(cell.character), attributes: attrs))
            }
            
            // Add newline for all rows to maintain consistent grid height/width
            // even for the last row (this ensures the formula (row*(cols+1))+col works)
            result.append(NSAttributedString(string: "\n"))
        }
        
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: result)
        textStorage.endEditing()
    }
    
    /// Calculate the text position in the rendered string from buffer cursor coordinates
    /// The rendered string has variable-length rows (trimmed trailing spaces)
    /// We need to count characters up to the cursor position
    func cursorTextPosition(in buffer: TerminalScreenBuffer) -> Int {
        // (row * (columns + 1)) + column
        // columns + 1 accounts for the newline character at the end of each row
        return (buffer.cursorRow * (buffer.columns + 1)) + buffer.cursorColumn
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
