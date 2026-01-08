//
//  FileTools.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation
import Combine

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
    
    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for read_file")
        }
        let url = try pathValidator.validateAndResolve(path)
        return try fileSystemService.readFile(at: url)
    }
}

/// Write content to a file
struct WriteFileTool: AITool {
    let name = "write_file"
    let description = "Write content to a file at the specified path. Overwrites if it exists."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "The absolute path to the file."
                ],
                "content": [
                    "type": "string",
                    "description": "The content to write to the file."
                ]
            ],
            "required": ["path", "content"]
        ]
    }
    
    let fileSystemService: FileSystemService
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol
    
    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for write_file")
        }
        guard let content = arguments["content"] as? String else {
            throw AppError.aiServiceError("Missing 'content' argument for write_file")
        }
        let url = try pathValidator.validateAndResolve(path)
        await AIToolTraceLogger.shared.log(type: "fs.write_file", data: [
            "path": pathValidator.relativePath(for: url),
            "bytes": content.utf8.count
        ])
        let existed = FileManager.default.fileExists(atPath: url.path)
        try fileSystemService.writeFile(content: content, to: url)
        Task { @MainActor in
            if existed {
                eventBus.publish(FileModifiedEvent(url: url))
            } else {
                eventBus.publish(FileCreatedEvent(url: url))
            }
        }
        return "Successfully wrote to \(pathValidator.relativePath(for: url))"
    }
}

/// Write content to multiple files (preferred for scaffolding a project)
struct WriteFilesTool: AITool {
    let name = "write_files"
    let description = "Write content to multiple files. Overwrites existing files. Preferred for scaffolding multi-file changes in one operation."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "files": [
                    "type": "array",
                    "description": "List of files to write.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "Absolute path or project-root-relative path to the file."
                            ],
                            "content": [
                                "type": "string",
                                "description": "Content to write to the file."
                            ]
                        ],
                        "required": ["path", "content"]
                    ]
                ]
            ],
            "required": ["files"]
        ]
    }

    let fileSystemService: FileSystemService
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol

    func execute(arguments: [String: Any]) async throws -> String {
        guard let files = arguments["files"] as? [[String: Any]] else {
            throw AppError.aiServiceError("Missing 'files' argument for write_files")
        }

        if files.isEmpty {
            return "No files to write."
        }

        var results: [String] = []
        results.reserveCapacity(files.count)

        await AIToolTraceLogger.shared.log(type: "fs.write_files_start", data: [
            "count": files.count
        ])

        for entry in files {
            guard let path = entry["path"] as? String else {
                throw AppError.aiServiceError("Missing 'path' in a write_files entry")
            }
            guard let content = entry["content"] as? String else {
                throw AppError.aiServiceError("Missing 'content' in a write_files entry")
            }

            let url = try pathValidator.validateAndResolve(path)
            await AIToolTraceLogger.shared.log(type: "fs.write_files_entry", data: [
                "path": pathValidator.relativePath(for: url),
                "bytes": content.utf8.count
            ])
            let existed = FileManager.default.fileExists(atPath: url.path)
            try fileSystemService.writeFile(content: content, to: url)

            Task { @MainActor in
                if existed {
                    eventBus.publish(FileModifiedEvent(url: url))
                } else {
                    eventBus.publish(FileCreatedEvent(url: url))
                }
            }

            results.append(pathValidator.relativePath(for: url))
        }

        await AIToolTraceLogger.shared.log(type: "fs.write_files_done", data: [
            "count": results.count
        ])

        return "Successfully wrote \(results.count) file(s):\n" + results.joined(separator: "\n")
    }
}

/// Create a new empty file
struct CreateFileTool: AITool {
    let name = "create_file"
    let description = "Create a new empty file at the specified path."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "The absolute path where the file should be created."
                ]
            ],
            "required": ["path"]
        ]
    }
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol
    
    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for create_file")
        }
        let url = try pathValidator.validateAndResolve(path)
        let fileManager = FileManager.default

        await AIToolTraceLogger.shared.log(type: "fs.create_file", data: [
            "path": pathValidator.relativePath(for: url)
        ])
        if fileManager.fileExists(atPath: url.path) {
            return "Error: File already exists at \(pathValidator.relativePath(for: url))"
        }

        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
        try "".write(to: url, atomically: true, encoding: .utf8)
        Task { @MainActor in
            eventBus.publish(FileCreatedEvent(url: url))
        }
        return "Successfully created file at \(pathValidator.relativePath(for: url))"
    }
}

/// List files in a directory
struct ListFilesTool: AITool {
    let name = "list_files"
    let description = "List files and directories in the specified path."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "The absolute path to the directory."
                ]
            ],
            "required": ["path"]
        ]
    }
    let pathValidator: PathValidator
    
    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for list_files")
        }
        let url = try pathValidator.validateAndResolve(path)
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let fileNames = contents.map { $0.lastPathComponent }
        return fileNames.joined(separator: "\n")
    }
}

/// Delete a file
struct DeleteFileTool: AITool {
    let name = "delete_file"
    let description = "Delete a file at the specified path."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "The absolute path to the file to delete."
                ]
            ],
            "required": ["path"]
        ]
    }
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol
    
    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for delete_file")
        }
        let url = try pathValidator.validateAndResolve(path)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            return "Error: File does not exist at \(pathValidator.relativePath(for: url))"
        }
        try fileManager.removeItem(at: url)
        Task { @MainActor in
            eventBus.publish(FileDeletedEvent(url: url))
        }
        return "Successfully deleted file at \(pathValidator.relativePath(for: url))"
    }
}

/// Replace specific content in a file (diff-style editing)
struct ReplaceInFileTool: AITool {
    let name = "replace_in_file"
    let description = "Replace specific content in a file. Use this instead of write_file for large files to avoid rewriting everything. Specify the exact text to find and what to replace it with."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "The absolute path to the file."
                ],
                "old_text": [
                    "type": "string",
                    "description": "The exact text to find and replace. Must match exactly including whitespace."
                ],
                "new_text": [
                    "type": "string",
                    "description": "The new text to replace the old text with."
                ]
            ],
            "required": ["path", "old_text", "new_text"]
        ]
    }
    
    let fileSystemService: FileSystemService
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol
    
    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for replace_in_file")
        }
        guard let oldText = arguments["old_text"] as? String else {
            throw AppError.aiServiceError("Missing 'old_text' argument for replace_in_file")
        }
        guard let newText = arguments["new_text"] as? String else {
            throw AppError.aiServiceError("Missing 'new_text' argument for replace_in_file")
        }
        
        let url = try pathValidator.validateAndResolve(path)
        let content = try fileSystemService.readFile(at: url)
        
        if !content.contains(oldText) {
            return "Error: Could not find the specified old_text in the file. Make sure it matches exactly."
        }
        
        let newContent = content.replacingOccurrences(of: oldText, with: newText)
        try fileSystemService.writeFile(content: newContent, to: url)
        Task { @MainActor in
            eventBus.publish(FileModifiedEvent(url: url))
        }
        
        return "Successfully replaced content in \(pathValidator.relativePath(for: url))"
    }
}
