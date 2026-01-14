//
//  LanguageDetector.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation

public struct LanguageDetector {
    public static func detect(at url: URL) -> CodeLanguage {
        let pathExtension = url.pathExtension.lowercased()

        switch pathExtension {
        case "swift":
            return .swift
        case "js", "jsx":
            return .javascript
        case "ts", "tsx":
            return .typescript
        case "py":
            return .python
        case "html":
            return .html
        case "css":
            return .css
        case "json":
            return .json
        case "yaml", "yml":
            return .yaml
        case "md", "markdown":
            return .markdown
        default:
            return .unknown
        }
    }
}
