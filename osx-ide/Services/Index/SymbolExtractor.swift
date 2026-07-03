import Foundation

public struct ExtractedSymbol: Sendable {
    public let name: String
    public let kind: String
    public let scope: String
    public let signature: String
    public let parentName: String
    public let lineStart: Int
    public let lineEnd: Int
    public let filePath: String
}

public enum SymbolExtractor {
    public static func extract(from url: URL, content: String) -> [ExtractedSymbol] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return extractSwift(content: content, filePath: url.path)
        case "js", "jsx", "mjs": return extractJSTS(content: content, filePath: url.path)
        case "ts", "tsx": return extractJSTS(content: content, filePath: url.path)
        case "py": return extractPython(content: content, filePath: url.path)
        default: return []
        }
    }
}

// MARK: - Swift

private let swiftScopePattern = try! NSRegularExpression(pattern: "\\b(public|private|internal|fileprivate|open|static|class)\\b")
private let swiftSignaturePattern = try! NSRegularExpression(pattern: "\\(.*?\\)\\s*(async)?\\s*(throws)?\\s*->\\s*[^\\{;]+")

private func extractSwift(content: String, filePath: String) -> [ExtractedSymbol] {
    let lines = content.components(separatedBy: .newlines)
    var symbols: [ExtractedSymbol] = []
    var braceDepth = 0
    var lastTypeName = ""
    var lastTypeDepth = -1

    for (lineIndex, line) in lines.enumerated() {
        let lineNum = lineIndex + 1
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Track brace depth for parent-child
        for ch in line {
            if ch == "{" { braceDepth += 1 }
            if ch == "}" { braceDepth -= 1 }
        }

        // Type declarations: class, struct, enum, protocol, actor, extension
        if let m = tryMatch(trimmed, pattern: "\\b(actor|class|struct|enum|protocol|extension)\\s+([A-Za-z_]\\w*)") {
            let kind = m[1]
            let name = m[2]
            let scope = extractSwiftScope(from: trimmed)
            let parent = kind == "extension" ? name : "" // extensions reference their type
            symbols.append(ExtractedSymbol(name: name, kind: kind, scope: scope, signature: "", parentName: parent, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            if kind != "extension" {
                lastTypeName = name
                lastTypeDepth = braceDepth - 1
            }
            continue
        }

        // Methods/functions
        if let m = tryMatch(trimmed, pattern: "\\b(func|static\\s+func|class\\s+func)\\s+([A-Za-z_]\\w*)\\s*\\(") {
            let name = m[2]
            let scope = extractSwiftScope(from: trimmed)
            let sig = extractSwiftSignature(line: trimmed)
            symbols.append(ExtractedSymbol(name: name, kind: "method", scope: scope, signature: sig, parentName: lastTypeName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }

        // Properties
        if let m = tryMatch(trimmed, pattern: "\\b(var|let)\\s+([A-Za-z_]\\w*)\\s*[=:]") {
            let name = m[2]
            let scope = extractSwiftScope(from: trimmed)
            symbols.append(ExtractedSymbol(name: name, kind: "property", scope: scope, signature: "", parentName: lastTypeName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }

        // Typealias
        if let m = tryMatch(trimmed, pattern: "\\btypealias\\s+([A-Za-z_]\\w*)") {
            symbols.append(ExtractedSymbol(name: m[1], kind: "typealias", scope: "", signature: "", parentName: lastTypeName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }
    }

    return symbols
}

private func extractSwiftScope(from line: String) -> String {
    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    guard let match = swiftScopePattern.firstMatch(in: line, range: range) else { return "" }
    return String(line[Range(match.range(at: 1), in: line)!])
}

private func extractSwiftSignature(line: String) -> String {
    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    guard let match = swiftSignaturePattern.firstMatch(in: line, range: range) else { return "" }
    return String(line[Range(match.range(at: 0), in: line)!])
}

// MARK: - JS/TS

private func extractJSTS(content: String, filePath: String) -> [ExtractedSymbol] {
    let lines = content.components(separatedBy: .newlines)
    var symbols: [ExtractedSymbol] = []
    var braceDepth = 0
    var lastClassName = ""

    for (lineIndex, line) in lines.enumerated() {
        let lineNum = lineIndex + 1
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for ch in line {
            if ch == "{" { braceDepth += 1 }
            if ch == "}" { braceDepth -= 1 }
        }

        // class
        if let m = tryMatch(trimmed, pattern: "\\b(class|interface)\\s+([A-Za-z_]\\w*)") {
            let name = m[2]
            symbols.append(ExtractedSymbol(name: name, kind: m[1], scope: extractJSScope(from: trimmed), signature: "", parentName: "", lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            lastClassName = name
            continue
        }

        // function
        if let m = tryMatch(trimmed, pattern: "\\b(function|const|let|var)\\s+([A-Za-z_]\\w*)\\s*[=:(]") {
            let name = m[2]
            let kind = m[1] == "function" ? "function" : "variable"
            let scope = extractJSScope(from: trimmed)
            symbols.append(ExtractedSymbol(name: name, kind: kind, scope: scope, signature: "", parentName: lastClassName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }

        // export default function/class
        if let m = tryMatch(trimmed, pattern: "export\\s+(default\\s+)?(function|class)\\s+([A-Za-z_]\\w*)") {
            symbols.append(ExtractedSymbol(name: m[3], kind: m[2], scope: "export", signature: "", parentName: lastClassName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }
    }

    return symbols
}

private func extractJSScope(from line: String) -> String {
    if line.contains("export ") { return "export" }
    return ""
}

// MARK: - Python

private func extractPython(content: String, filePath: String) -> [ExtractedSymbol] {
    let lines = content.components(separatedBy: .newlines)
    var symbols: [ExtractedSymbol] = []
    var lastClassName = ""
    var lastClassIndent = -1

    for (lineIndex, line) in lines.enumerated() {
        let lineNum = lineIndex + 1
        let indent = line.prefix(while: { $0 == " " }).count
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

        // class
        if let m = tryMatch(trimmed, pattern: "\\bclass\\s+([A-Za-z_]\\w*)\\s*[(:]") {
            let name = m[1]
            symbols.append(ExtractedSymbol(name: name, kind: "class", scope: "", signature: "", parentName: "", lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            lastClassName = name
            lastClassIndent = indent
            continue
        }

        // def (method or function)
        if let m = tryMatch(trimmed, pattern: "\\bdef\\s+([A-Za-z_]\\w*)\\s*\\(") {
            let name = m[1]
            let kind = (indent > lastClassIndent && !lastClassName.isEmpty) ? "method" : "function"
            let parent = kind == "method" ? lastClassName : ""
            symbols.append(ExtractedSymbol(name: name, kind: kind, scope: "", signature: "", parentName: parent, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }
    }

    return symbols
}

// MARK: - Helpers

private func tryMatch(_ text: String, pattern: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }
    var groups: [String] = []
    for i in 0..<match.numberOfRanges {
        if let r = Range(match.range(at: i), in: text) {
            groups.append(String(text[r]))
        }
    }
    return groups
}
