//
//  ReadFileTool.swift
//  osx-ide
//
//  Created by AI Assistant on 11/01/2026.
//

import Foundation

/// Read content of a file
struct ReadFileTool: AITool {
    let name = "read_file"
    let description = "Read the contents of a file at the specified path."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "The absolute path to the file to read."
                ],
                "start_line": [
                    "type": "integer",
                    "description": "Optional 1-based start line to read from."
                ],
                "end_line": [
                    "type": "integer",
                    "description": "Optional 1-based end line to read through (inclusive)."
                ]
            ],
            "required": ["path"]
        ]
    }

    let fileSystemService: FileSystemService
    let pathValidator: PathValidator

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for read_file")
        }
        let url = try pathValidator.validateAndResolve(path)
        let content = try fileSystemService.readFile(at: url)

        let startLine = parseLineNumber(arguments["start_line"])
        let endLine = parseLineNumber(arguments["end_line"])

        guard startLine != nil || endLine != nil else {
            return content
        }

        return extractLineRange(
            from: content,
            startLine: startLine ?? 1,
            endLine: endLine
        )
    }

    private func parseLineNumber(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as Int32:
            return Int(number)
        case let number as Int64:
            return Int(number)
        case let number as Double:
            return Int(number)
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func extractLineRange(from content: String, startLine: Int, endLine: Int?) -> String {
        let allLines = content.components(separatedBy: .newlines)
        guard !allLines.isEmpty else { return "" }

        let safeStart = max(1, startLine)
        let safeEnd = min(max(safeStart, endLine ?? allLines.count), allLines.count)

        let indexedSlice = (safeStart...safeEnd).map { lineNumber in
            "\(lineNumber): \(allLines[lineNumber - 1])"
        }
        return indexedSlice.joined(separator: "\n")
    }
}
