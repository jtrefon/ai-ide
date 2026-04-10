import Foundation

@MainActor
struct CompletionContextAssembler {
    private let prefixCharacterLimit = 4_000
    private let suffixCharacterLimit = 1_200
    private let symbolLimit = 8

    func buildContext(from snapshot: InlineCompletionEditorSnapshot) -> CompletionContextPayload {
        let nsBuffer = snapshot.buffer as NSString
        let safeCursor = max(0, min(snapshot.cursorPosition, nsBuffer.length))

        let prefixStart = max(0, safeCursor - prefixCharacterLimit)
        let suffixEnd = min(nsBuffer.length, safeCursor + suffixCharacterLimit)

        let prefix = nsBuffer.substring(with: NSRange(location: prefixStart, length: safeCursor - prefixStart))
        let suffix = nsBuffer.substring(with: NSRange(location: safeCursor, length: suffixEnd - safeCursor))

        return CompletionContextPayload(
            prefix: prefix,
            suffix: suffix,
            scopeSummary: nearestScopeSummary(in: nsBuffer, cursor: safeCursor),
            symbols: extractedSymbols(near: prefix)
        )
    }

    private func nearestScopeSummary(in buffer: NSString, cursor: Int) -> String? {
        let searchWindow = max(0, cursor - 1_500)
        let snippet = buffer.substring(with: NSRange(location: searchWindow, length: cursor - searchWindow))
        let lines = snippet.components(separatedBy: .newlines).reversed()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("func ") ||
                trimmed.hasPrefix("class ") ||
                trimmed.hasPrefix("struct ") ||
                trimmed.hasPrefix("enum ") ||
                trimmed.hasPrefix("protocol ") ||
                trimmed.hasPrefix("extension ") {
                return trimmed
            }
        }
        return nil
    }

    private func extractedSymbols(near prefix: String) -> [String] {
        let scanner = prefix.suffix(600)
        let matches = scanner.matches(of: /[A-Za-z_][A-Za-z0-9_]*/)
            .map { String($0.0) }
            .filter { $0.count > 2 }

        var seen = Set<String>()
        var ordered: [String] = []
        for symbol in matches.reversed() {
            let lowered = symbol.lowercased()
            if seen.insert(lowered).inserted {
                ordered.append(symbol)
            }
            if ordered.count >= symbolLimit {
                break
            }
        }
        return ordered
    }
}

