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
        
        // DEBUG: Log buffer state before rendering
        print("[DEBUG TerminalScreenRenderer] render() - buffer cursorRow: \(buffer.cursorRow), cursorColumn: \(buffer.cursorColumn)")
        print("[DEBUG TerminalScreenRenderer] render() - buffer rows: \(buffer.rows), columns: \(buffer.columns)")
        
        let result = NSMutableAttributedString()
        
        for row in 0..<buffer.rows {
            for col in 0..<buffer.columns {
                let cell = buffer.grid[row][col]
                let attrs = attributesForCell(cell, fontSize: fontSize, fontFamily: fontFamily)
                result.append(NSAttributedString(string: String(cell.character), attributes: attrs))
            }
            // Add newline except for last row
            if row < buffer.rows - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        
        // DEBUG: Log rendered string length and preview
        let renderedString = result.string
        print("[DEBUG TerminalScreenRenderer] render() - rendered string length: \(renderedString.count)")
        print("[DEBUG TerminalScreenRenderer] render() - rendered string preview (first 200 chars): \(String(renderedString.prefix(200)))")
        print("[DEBUG TerminalScreenRenderer] render() - newline count in rendered string: \(renderedString.filter { $0 == "\n" }.count)")
        
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: result)
        textStorage.endEditing()
        
        // DEBUG: Log text view's selectedRange after rendering
        print("[DEBUG TerminalScreenRenderer] render() - textView.selectedRange before update: \(textView.selectedRange())")
    }
    
    /// Calculate the text position in the rendered string from buffer cursor coordinates
    /// The rendered string has the format: each row has `columns` characters followed by a newline (except the last row)
    /// So for cursor at (row, column), the text position is: row * (columns + 1) + column
    func cursorTextPosition(in buffer: TerminalScreenBuffer) -> Int {
        let position = buffer.cursorRow * (buffer.columns + 1) + buffer.cursorColumn
        // Clamp to valid range
        let maxPosition = buffer.rows * buffer.columns + (buffer.rows - 1) // total chars + newlines
        return min(position, maxPosition)
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
