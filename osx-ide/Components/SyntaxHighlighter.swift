import AppKit

@MainActor
final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    private init() {}

    func highlight(
        _ code: String,
        language: String = "text",
        font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    ) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        return NSAttributedString(string: code, attributes: attributes)
    }
}
