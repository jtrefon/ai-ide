import Foundation

public struct JavaScriptParser {
    public static func parse(content: String, resourceId: String) -> [Symbol] {
        parseCommonJSLike(content: content, resourceId: resourceId)
    }

    static func parseCommonJSLike(content: String, resourceId: String) -> [Symbol] {
        var symbols: [Symbol] = []
        let lines = content.components(separatedBy: .newlines)

        let patterns: [(kind: SymbolKind, pattern: String)] = [
            (.class, #"^\s*(?:export\s+)?class\s+([A-Z][A-Za-z0-9_]*)"#),
            (.function, #"^\s*(?:export\s+)?function\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\("#),
            (.function, #"^\s*(?:export\s+)?const\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*\([^)]*\)\s*=>"#),
            (.function, #"^\s*(?:export\s+)?let\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*\([^)]*\)\s*=>"#),
            (.variable, #"^\s*(?:export\s+)?(?:const|let|var)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*="#)
        ]

        for (i, line) in lines.enumerated() {
            let lineNum = i + 1
            for (kind, pattern) in patterns {
                if let match = matchRegex(pattern, in: line) {
                    let name = match
                    let id = "\(resourceId):\(lineNum):\(name)"
                    symbols.append(Symbol(id: id, resourceId: resourceId, name: name, kind: kind, lineStart: lineNum, lineEnd: lineNum, description: nil))
                    break
                }
            }
        }

        return symbols
    }

    private static func matchRegex(_ pattern: String, in text: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

            if let result = results.first, result.numberOfRanges > 1 {
                return nsString.substring(with: result.range(at: 1))
            }
        } catch {
            print("Invalid regex: \(pattern)")
        }
        return nil
    }
}
