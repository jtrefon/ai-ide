//
//  CodeFormatter.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation

public struct CodeFormatter {
    public static func format(_ code: String, language: CodeLanguage) -> String {
        let lines = code.components(separatedBy: .newlines)
        var formattedLines: [String] = []
        var indentLevel = 0
        let indentString = IndentationStyle.current().indentUnit(tabWidth: AppConstants.Editor.tabWidth)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty {
                formattedLines.append("")
                continue
            }
            
            // Adjust indent level for closing braces/brackets
            let closeCount = trimmedLine.filter { $0 == "}" || $0 == "]" || $0 == ")" }.count
            let openCount = trimmedLine.filter { $0 == "{" || $0 == "[" || $0 == "(" }.count
            
            // Special handling for lines starting with a closing brace
            if trimmedLine.hasPrefix("}") || trimmedLine.hasPrefix("]") || trimmedLine.hasPrefix(")") {
                indentLevel = max(0, indentLevel - 1)
            }
            
            let currentIndent = String(repeating: indentString, count: indentLevel)
            
            // Format braces: make sure they are wrapped or spaced consistently
            // This is a simple implementation, more complex logic could be added per language
            var processedLine = trimmedLine
            
            // Adjust level for next lines if this line had more opening than closing
            if openCount > closeCount {
                if !trimmedLine.hasPrefix("}") && !trimmedLine.hasPrefix("]") && !trimmedLine.hasPrefix(")") {
                    // Already decremented if it started with one
                }
                indentLevel += (openCount - closeCount)
            } else if closeCount > openCount {
                // If it didn't start with a closing brace but contains one that closes a previous scope
                if !trimmedLine.hasPrefix("}") && !trimmedLine.hasPrefix("]") && !trimmedLine.hasPrefix(")") {
                    indentLevel = max(0, indentLevel - (closeCount - openCount))
                }
            }
            
            formattedLines.append(currentIndent + processedLine)
        }
        
        return formattedLines.joined(separator: "\n")
    }
}
