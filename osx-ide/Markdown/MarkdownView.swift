import SwiftUI

struct MarkdownView<CodeBlockContent: View>: View {
    private let document: MarkdownDocument
    private let codeBlock: (String, String?) -> CodeBlockContent

    init(markdown: String, @ViewBuilder codeBlock: @escaping (String, String?) -> CodeBlockContent) {
        self.document = MarkdownDocument.parse(markdown)
        self.codeBlock = codeBlock
    }

    init(document: MarkdownDocument, @ViewBuilder codeBlock: @escaping (String, String?) -> CodeBlockContent) {
        self.document = document
        self.codeBlock = codeBlock
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(document.blocks) { block in
                switch block.kind {
                case .richText(let markdownText):
                    MarkdownRichTextView(markdown: markdownText)
                case .code(let code, let language):
                    codeBlock(code, language)
                case .horizontalRule:
                    Divider()
                }
            }
        }
    }
}

private struct MarkdownRichTextView: View {
    let markdown: String

    var body: some View {
        let normalized = normalizeMarkdownLineBreaks(markdown)
        if let attributed = try? AttributedString(
            markdown: normalized,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(normalized)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func normalizeMarkdownLineBreaks(_ input: String) -> String {
        // AttributedString(markdown:) follows CommonMark semantics where single newlines
        // are treated as spaces. Chat output often uses single newlines for formatting,
        // so we convert them to hard breaks to preserve visual structure.
        var text = input
        // Models sometimes emit headings like "**Title**Body" without a separating space.
        // Insert a single space after closing emphasis markers when followed by a word character.
        text = text.replacingOccurrences(
            of: "(?<=\\w)(\\*\\*|__)(?=\\w)",
            with: "$1 ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: "\u{2028}", with: "\n") // line separator
        text = text.replacingOccurrences(of: "\u{2029}", with: "\n") // paragraph separator
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return text }

        var out = ""
        out.reserveCapacity(text.count)

        for i in 0..<lines.count {
            let line = String(lines[i])
            out += line

            guard i < lines.count - 1 else { break }
            let nextLine = String(lines[i + 1])

            if line.isEmpty || nextLine.isEmpty {
                out += "\n"
            } else {
                out += "  \n"
            }
        }

        return out
    }
}
