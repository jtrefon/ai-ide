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
        return try fileSystemService.readFile(at: url)
    }
}
