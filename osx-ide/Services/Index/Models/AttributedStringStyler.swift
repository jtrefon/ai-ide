import Foundation
import AppKit

enum AttributedStringStyler {
    static func makeBaseAttributedString(
        code: String,
        font: NSFont,
        textColor: NSColor = NSColor.labelColor
    ) -> (attributed: NSMutableAttributedString, fullRange: NSRange) {
        let attributed = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)

        attributed.addAttributes([
            .font: font,
            .foregroundColor: textColor
        ], range: fullRange)

        return (attributed: attributed, fullRange: fullRange)
    }
}
