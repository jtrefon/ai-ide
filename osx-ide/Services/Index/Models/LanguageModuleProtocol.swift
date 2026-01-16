import AppKit
import Foundation

public protocol LanguageModule: Sendable {
    var id: CodeLanguage { get }
    var fileExtensions: [String] { get }

    func highlight(_ code: String, font: NSFont) -> NSAttributedString
    func parseSymbols(content: String, resourceId: String) -> [Symbol]
    func format(_ code: String) -> String
}
