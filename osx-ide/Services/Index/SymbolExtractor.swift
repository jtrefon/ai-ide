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
        case "php": return extractPHP(content: content, filePath: url.path)
        default: return []
        }
    }
}

// MARK: - Pattern cache

private let regexCache: [String: NSRegularExpression] = {
    let patterns = [
        "swift_type": "\\b(actor|class|struct|enum|protocol|extension)\\s+([A-Za-z_]\\w*)",
        "swift_method": "\\b(func|static\\s+func|class\\s+func)\\s+([A-Za-z_]\\w*)\\s*\\(",
        "swift_property": "\\b(var|let)\\s+([A-Za-z_]\\w*)\\s*[=:]",
        "swift_typealias": "\\btypealias\\s+([A-Za-z_]\\w*)",
        "swift_scope": "\\b(public|private|internal|fileprivate|open|static|class)\\b",
        "swift_sig": "\\(.*?\\)\\s*(async)?\\s*(throws)?\\s*->\\s*[^\\{;]+",
        "jsts_class": "\\b(class|interface)\\s+([A-Za-z_]\\w*)",
        "jsts_func": "\\b(function|const|let|var)\\s+([A-Za-z_]\\w*)\\s*[=:(]",
        "jsts_export": "export\\s+(default\\s+)?(function|class)\\s+([A-Za-z_]\\w*)",
        "py_class": "\\bclass\\s+([A-Za-z_]\\w*)\\s*[(:]",
        "py_def": "\\bdef\\s+([A-Za-z_]\\w*)\\s*\\(",
        "php_class": "\\b(class|interface|trait)\\s+([A-Za-z_]\\w*)",
        "php_function": "\\bfunction\\s+([A-Za-z_]\\w*)\\s*\\(",
        "php_scope": "\\b(public|private|protected|static)\\b",
        "php_property": "\\b(public|private|protected)\\s+\\$([A-Za-z_]\\w*)",
    ]
    var cache: [String: NSRegularExpression] = [:]
    for (key, pattern) in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern) {
            cache[key] = regex
        }
    }
    return cache
}()

private func match(_ text: String, key: String) -> [String]? {
    guard let regex = regexCache[key] else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }
    var groups: [String] = []
    for i in 0..<match.numberOfRanges {
        guard let r = Range(match.range(at: i), in: text) else { continue }
        groups.append(String(text[r]))
    }
    return groups
}

// MARK: - Swift

private func extractSwift(content: String, filePath: String) -> [ExtractedSymbol] {
    let lines = content.components(separatedBy: .newlines)
    var symbols: [ExtractedSymbol] = []
    var lastTypeName = ""

    for (lineIndex, line) in lines.enumerated() {
        let lineNum = lineIndex + 1
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let m = match(trimmed, key: "swift_type") {
            let kind = m[1]
            let name = m[2]
            let scope = extractSwiftScope(from: trimmed)
            let parent = kind == "extension" ? name : ""
            symbols.append(ExtractedSymbol(name: name, kind: kind, scope: scope, signature: "", parentName: parent, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            if kind != "extension" { lastTypeName = name }
            continue
        }

        if let m = match(trimmed, key: "swift_method") {
            let name = m[2]
            let scope = extractSwiftScope(from: trimmed)
            let sig = extractSwiftSignature(line: trimmed)
            symbols.append(ExtractedSymbol(name: name, kind: "method", scope: scope, signature: sig, parentName: lastTypeName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }

        if let m = match(trimmed, key: "swift_property") {
            let name = m[2]
            let scope = extractSwiftScope(from: trimmed)
            symbols.append(ExtractedSymbol(name: name, kind: "property", scope: scope, signature: "", parentName: lastTypeName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }

        if let m = match(trimmed, key: "swift_typealias") {
            symbols.append(ExtractedSymbol(name: m[1], kind: "typealias", scope: "", signature: "", parentName: lastTypeName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }
    }

    return symbols
}

private func extractSwiftScope(from line: String) -> String {
    guard let m = match(line, key: "swift_scope"), m.count > 1 else { return "" }
    return m[1]
}

private func extractSwiftSignature(line: String) -> String {
    guard let m = match(line, key: "swift_sig"), m.count > 0 else { return "" }
    return m[0]
}

// MARK: - JS/TS

private func extractJSTS(content: String, filePath: String) -> [ExtractedSymbol] {
    let lines = content.components(separatedBy: .newlines)
    var symbols: [ExtractedSymbol] = []
    var lastClassName = ""

    for (lineIndex, line) in lines.enumerated() {
        let lineNum = lineIndex + 1
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let m = match(trimmed, key: "jsts_class") {
            symbols.append(ExtractedSymbol(name: m[2], kind: m[1], scope: extractJSScope(from: trimmed), signature: "", parentName: "", lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            lastClassName = m[2]
            continue
        }

        if let m = match(trimmed, key: "jsts_func") {
            let kind = m[1] == "function" ? "function" : "variable"
            symbols.append(ExtractedSymbol(name: m[2], kind: kind, scope: extractJSScope(from: trimmed), signature: "", parentName: lastClassName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }

        if let m = match(trimmed, key: "jsts_export") {
            symbols.append(ExtractedSymbol(name: m[3], kind: m[2], scope: "export", signature: "", parentName: lastClassName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }
    }

    return symbols
}

private func extractJSScope(from line: String) -> String {
    line.contains("export ") ? "export" : ""
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

        if let m = match(trimmed, key: "py_class") {
            symbols.append(ExtractedSymbol(name: m[1], kind: "class", scope: "", signature: "", parentName: "", lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            lastClassName = m[1]
            lastClassIndent = indent
            continue
        }

        if let m = match(trimmed, key: "py_def") {
            let isMethod = indent > lastClassIndent && !lastClassName.isEmpty
            symbols.append(ExtractedSymbol(name: m[1], kind: isMethod ? "method" : "function", scope: "", signature: "", parentName: isMethod ? lastClassName : "", lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }
    }

    return symbols
}

private func extractPHP(content: String, filePath: String) -> [ExtractedSymbol] {
    let lines = content.components(separatedBy: .newlines)
    var symbols: [ExtractedSymbol] = []
    var lastClassName = ""

    for (lineIndex, line) in lines.enumerated() {
        let lineNum = lineIndex + 1
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("//"), !trimmed.hasPrefix("#"), !trimmed.hasPrefix("/*") else { continue }

        if let m = match(trimmed, key: "php_class") {
            symbols.append(ExtractedSymbol(name: m[2], kind: m[1], scope: extractPHPScope(from: trimmed), signature: "", parentName: "", lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            lastClassName = m[2]
            continue
        }

        if let m = match(trimmed, key: "php_function") {
            let scope = extractPHPScope(from: trimmed)
            symbols.append(ExtractedSymbol(name: m[1], kind: "function", scope: scope, signature: "", parentName: lastClassName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }

        if let m = match(trimmed, key: "php_property") {
            symbols.append(ExtractedSymbol(name: m[2], kind: "property", scope: m[1], signature: "", parentName: lastClassName, lineStart: lineNum, lineEnd: lineNum, filePath: filePath))
            continue
        }
    }

    return symbols
}

private func extractPHPScope(from line: String) -> String {
    guard let m = match(line, key: "php_scope"), m.count > 1 else { return "" }
    return m[1]
}
