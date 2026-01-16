import Foundation

struct MarkdownBlock: Equatable, Identifiable {
    enum Kind: Equatable {
        case richText(String)
        case code(code: String, language: String?)
        case horizontalRule
    }

    let id: UUID
    let kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    static func richText(_ text: String) -> MarkdownBlock {
        MarkdownBlock(kind: .richText(text))
    }

    static func code(code: String, language: String?) -> MarkdownBlock {
        MarkdownBlock(kind: .code(code: code, language: language))
    }

    static var horizontalRule: MarkdownBlock {
        MarkdownBlock(kind: .horizontalRule)
    }
}
