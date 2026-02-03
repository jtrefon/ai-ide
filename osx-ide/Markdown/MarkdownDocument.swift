import Foundation

struct MarkdownDocument: Equatable {
    let blocks: [MarkdownBlock]

    static func parse(_ input: String) -> MarkdownDocument {
        MarkdownParser.parse(input)
    }
}
