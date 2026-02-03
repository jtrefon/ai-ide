import AppKit
import Foundation

enum LanguageKeywordHighlighter {
    struct HighlightContext {
        let color: NSColor
        let attributedString: NSMutableAttributedString
        let code: String
        let helper: RegexLanguageModule
    }

    struct HighlightRequest {
        let words: [String]
        let context: HighlightContext
    }

    static func highlight(_ request: HighlightRequest) {
        request.context.helper.highlightWholeWords(
            request.words,
            color: request.context.color,
            in: request.context.attributedString,
            code: request.context.code
        )
    }
}
