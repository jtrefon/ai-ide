import AppKit
import Foundation

@available(*, deprecated, message: "Regex highlighting is removed. Use TokenLanguageModule.")
open class RegexLanguageModule: LanguageModule, @unchecked Sendable {
    public let id: CodeLanguage
    public let fileExtensions: [String]

    public init(id: CodeLanguage, fileExtensions: [String]) {
        self.id = id
        self.fileExtensions = fileExtensions
    }

    open func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let (attributed, _) = AttributedStringStyler.makeBaseAttributedString(code: code, font: font)
        return attributed
    }

    open func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return []
    }

    open func format(_ code: String) -> String {
        return code
    }
}
