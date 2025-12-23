//
//  IndexModels.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation

public enum CodeLanguage: String, Codable, Sendable {
    case swift
    case javascript
    case typescript
    case python
    case html
    case css
    case json
    case yaml
    case markdown
    case unknown
}

public struct IndexConfiguration: Codable, Sendable {
    public var enabled: Bool
    public var debounceMs: Int
    public var excludePatterns: [String]
    
    public static let `default` = IndexConfiguration(
        enabled: true,
        debounceMs: 300,
        excludePatterns: [
            "*.generated.*",
            "Pods/*",
            "node_modules/*",
            ".build/*",
            ".git/*",
            ".ide/*"
        ]
    )
}

public struct IndexedResource {
    public let id: String
    public let url: URL
    public let language: CodeLanguage
    public let lastModified: Date
    public let contentHash: String
}

public enum SymbolKind: String, Codable, Sendable {
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case `extension`
    case function
    case variable
    case initializer
    case unknown
}

public struct Symbol: Codable, Sendable {
    public let id: String
    public let resourceId: String
    public let name: String
    public let kind: SymbolKind
    public let lineStart: Int
    public let lineEnd: Int
    public let description: String?
    
    public init(id: String, resourceId: String, name: String, kind: SymbolKind, lineStart: Int, lineEnd: Int, description: String? = nil) {
        self.id = id
        self.resourceId = resourceId
        self.name = name
        self.kind = kind
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.description = description
    }
}
