import Foundation

enum LanguageKeywordRepository {
    static let javascript: [String] = [
        "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
        "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in",
        "instanceof", "let", "new", "return", "super", "switch", "this", "throw", "try",
        "typeof", "var", "void", "while", "with", "yield", "async", "await"
    ]

    static let typescriptExtras: [String] = [
        "interface", "type", "implements", "namespace", "abstract",
        "public", "private", "protected", "readonly"
    ]

    static let swiftKeywords: [String] = [
        "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
        "if", "else", "for", "while", "repeat", "switch", "case", "default", "break",
        "continue", "defer", "do", "catch", "throw", "throws", "rethrows", "try", "in",
        "where", "return", "as", "is", "nil", "true", "false", "init", "deinit",
        "subscript", "typealias", "associatedtype", "mutating", "nonmutating", "static",
        "final", "open", "public", "internal", "fileprivate", "private", "guard", "some",
        "any", "actor", "await", "async", "yield", "inout"
    ]

    static let swiftTypes: [String] = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Float", "Double", "Bool", "String", "Character",
        "Array", "Dictionary", "Set", "Optional", "Void", "Any", "AnyObject"
    ]

    static let python: [String] = [
        "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
        "continue", "def", "del", "elif", "else", "except", "finally", "for", "from",
        "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass",
        "raise", "return", "try", "while", "with", "yield"
    ]
}
