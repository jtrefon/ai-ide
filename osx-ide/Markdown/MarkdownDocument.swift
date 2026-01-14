import Foundation

struct MarkdownDocument: Equatable {
    let blocks: [MarkdownBlock]

    static func parse(_ input: String) -> MarkdownDocument {
        MarkdownParser.parse(input)
    }
}

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

enum MarkdownParser {
    static func parse(_ input: String) -> MarkdownDocument {
        let segments = splitFencedCodeBlocks(input)
        var blocks: [MarkdownBlock] = []

        for segment in segments {
            switch segment {
            case .text(let text):
                blocks.append(contentsOf: splitHorizontalRules(text))
            case .code(let code, let language):
                blocks.append(.code(code: code, language: language))
            }
        }

        return MarkdownDocument(blocks: blocks)
    }

    private enum Segment {
        case text(String)
        case code(String, String?)
    }

    private static func splitFencedCodeBlocks(_ input: String) -> [Segment] {
        var segments: [Segment] = []
        let codeBlockPattern = "```([a-zA-Z0-9+\\-]*)\\n?([\\s\\S]*?)```"

        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) else {
            return [.text(input)]
        }

        let nsString = input as NSString
        let matches = regex.matches(in: input, options: [], range: NSRange(location: 0, length: nsString.length))

        var lastLocation = 0

        for match in matches {
            let textRange = NSRange(location: lastLocation, length: match.range.location - lastLocation)
            if textRange.length > 0 {
                segments.append(.text(nsString.substring(with: textRange)))
            }

            var language: String?
            if match.range(at: 1).length > 0 {
                let lang = nsString.substring(with: match.range(at: 1))
                language = lang.isEmpty ? nil : lang
            }

            let codeRange = match.range(at: 2)
            let code = nsString.substring(with: codeRange).trimmingCharacters(in: .newlines)
            segments.append(.code(code, language))

            lastLocation = match.range.location + match.range.length
        }

        if lastLocation < nsString.length {
            let remainingRange = NSRange(location: lastLocation, length: nsString.length - lastLocation)
            segments.append(.text(nsString.substring(with: remainingRange)))
        }

        if segments.isEmpty {
            segments.append(.text(input))
        }

        return segments
    }

    private static func splitHorizontalRules(_ input: String) -> [MarkdownBlock] {
        // Markdown horizontal rule is a line containing at least 3 -, *, or _ (possibly separated by spaces)
        // We'll detect common forms like: --- , *** , ___ and ensure it's not part of text.
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        var blocks: [MarkdownBlock] = []
        var buffer: [Substring] = []

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            let text = buffer.joined(separator: "\n")
            blocks.append(.richText(String(text)))
            buffer.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if isHorizontalRuleLine(String(line)) {
                flushBuffer()
                blocks.append(.horizontalRule)
            } else {
                buffer.append(line)
            }
        }

        flushBuffer()
        return blocks
    }

    private static func isHorizontalRuleLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Remove spaces to allow "- - -"
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }

        let allowed: Set<Character>
        if compact.allSatisfy({ $0 == "-" }) {
            allowed = ["-"]
        } else if compact.allSatisfy({ $0 == "*" }) {
            allowed = ["*"]
        } else if compact.allSatisfy({ $0 == "_" }) {
            allowed = ["_"]
        } else {
            return false
        }

        return compact.allSatisfy { allowed.contains($0) }
    }
}
