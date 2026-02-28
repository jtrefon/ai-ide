import AppKit
import Foundation

public enum LanguageModuleCapability: String, CaseIterable, Sendable {
    case highlight
    case symbols
    case format
    case lint
}

public protocol LanguageModule: Sendable {
    var id: CodeLanguage { get }
    var fileExtensions: [String] { get }
    var capabilities: Set<LanguageModuleCapability> { get }

    func highlight(_ code: String, font: NSFont) -> NSAttributedString
    func parseSymbols(content: String, resourceId: String) -> [Symbol]
    func format(_ code: String) -> String
}

public extension LanguageModule {
    var capabilities: Set<LanguageModuleCapability> {
        [.highlight, .symbols, .format]
    }
}
