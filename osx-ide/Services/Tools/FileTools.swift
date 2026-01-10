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
                ],
                "mode": [
                    "type": "string",
                    "description": "One of: apply, propose. Default: apply.",
                    "enum": ["apply", "propose"]
                ],
                "patch_set_id": [
                    "type": "string",
                    "description": "Patch set identifier to stage into when mode=propose."
                ]
            ],
            "required": ["path", "content"]
        ]
    }
    
    let fileSystemService: FileSystemService
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol

    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let keys = arguments.keys.sorted().joined(separator: ", ")
            throw AppError.aiServiceError(
                "Missing 'path' argument for write_file. Provided keys: [\(keys)]. "
                    + "Fix: include a non-empty path (absolute or project-root-relative). Example:\n"
                    + "{\n  \"path\": \"src/App.css\",\n  \"content\": \"/* ... */\"\n}"
            )
        }
        guard let content = arguments["content"] as? String else {
            throw AppError.aiServiceError("Missing 'content' argument for write_file")
        }

        let mode = (arguments["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "apply"
        let toolCallId = (arguments["_tool_call_id"] as? String) ?? UUID().uuidString
        let patchSetId = (arguments["patch_set_id"] as? String)
            ?? (arguments["_conversation_id"] as? String)
            ?? "default"

        let url = try pathValidator.validateAndResolve(path)
        let relativePath = pathValidator.relativePath(for: url)

        if mode == "propose" {
            try await PatchSetStore.shared.stageWrite(
                patchSetId: patchSetId,
                toolCallId: toolCallId,
                relativePath: relativePath,
                content: content
            )
            await AIToolTraceLogger.shared.log(type: "fs.write_file_proposed", data: [
                "path": relativePath,
                "bytes": content.utf8.count,
                "patchSetId": patchSetId
            ])
            return "Proposed write to \(relativePath) (patch_set_id=\(patchSetId))."
        }

        await AIToolTraceLogger.shared.log(type: "fs.write_file", data: [
            "path": relativePath,
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
        return "Successfully wrote to \(relativePath)"
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
                ],
                "mode": [
                    "type": "string",
                    "description": "One of: apply, propose. Default: apply.",
                    "enum": ["apply", "propose"]
                ],
                "patch_set_id": [
                    "type": "string",
                    "description": "Patch set identifier to stage into when mode=propose."
                ]
            ],
            "required": ["files"]
        ]
    }

    let fileSystemService: FileSystemService
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol

    private func executionContext(from arguments: [String: Any]) -> (mode: String, toolCallId: String, patchSetId: String) {
        let mode = (arguments["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "apply"
        let toolCallId = (arguments["_tool_call_id"] as? String) ?? UUID().uuidString
        let patchSetId = (arguments["patch_set_id"] as? String)
            ?? (arguments["_conversation_id"] as? String)
            ?? "default"
        return (mode: mode, toolCallId: toolCallId, patchSetId: patchSetId)
    }

    private func resolvedWriteFileEntry(from entry: [String: Any]) throws -> (url: URL, relativePath: String, content: String) {
        guard let path = entry["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' in a write_files entry")
        }
        guard let content = entry["content"] as? String else {
            throw AppError.aiServiceError("Missing 'content' in a write_files entry")
        }

        let url = try pathValidator.validateAndResolve(path)
        let relativePath = pathValidator.relativePath(for: url)
        return (url: url, relativePath: relativePath, content: content)
    }

    private func stageWrite(toolCallId: String, patchSetId: String, relativePath: String, content: String) async throws {
        try await PatchSetStore.shared.stageWrite(
            patchSetId: patchSetId,
            toolCallId: toolCallId,
            relativePath: relativePath,
            content: content
        )
    }

    private func applyWrite(url: URL, relativePath: String, content: String) async throws {
        await AIToolTraceLogger.shared.log(type: "fs.write_files_entry", data: [
            "path": relativePath,
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
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let files = arguments["files"] as? [[String: Any]] else {
            throw AppError.aiServiceError("Missing 'files' argument for write_files")
        }

        let context = executionContext(from: arguments)
        let mode = context.mode
        let toolCallId = context.toolCallId
        let patchSetId = context.patchSetId

        if files.isEmpty {
            return "No files to write."
        }

        var results: [String] = []
        results.reserveCapacity(files.count)

        await AIToolTraceLogger.shared.log(type: mode == "propose" ? "fs.write_files_propose_start" : "fs.write_files_start", data: [
            "count": files.count,
            "patchSetId": patchSetId
        ])

        for entry in files {
            let resolved = try resolvedWriteFileEntry(from: entry)
            if mode == "propose" {
                try await stageWrite(
                    toolCallId: toolCallId,
                    patchSetId: patchSetId,
                    relativePath: resolved.relativePath,
                    content: resolved.content
                )
                results.append(resolved.relativePath)
                continue
            }

            try await applyWrite(url: resolved.url, relativePath: resolved.relativePath, content: resolved.content)
            results.append(resolved.relativePath)
        }

        await AIToolTraceLogger.shared.log(type: mode == "propose" ? "fs.write_files_propose_done" : "fs.write_files_done", data: [
            "count": results.count,
            "patchSetId": patchSetId
        ])

        if mode == "propose" {
            return "Proposed \(results.count) file(s) (patch_set_id=\(patchSetId)):\n" + results.joined(separator: "\n")
        }
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
                ],
                "mode": [
                    "type": "string",
                    "description": "One of: apply, propose. Default: apply.",
                    "enum": ["apply", "propose"]
                ],
                "patch_set_id": [
                    "type": "string",
                    "description": "Patch set identifier to stage into when mode=propose."
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

        let mode = (arguments["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "apply"
        let toolCallId = (arguments["_tool_call_id"] as? String) ?? UUID().uuidString
        let patchSetId = (arguments["patch_set_id"] as? String)
            ?? (arguments["_conversation_id"] as? String)
            ?? "default"

        let url = try pathValidator.validateAndResolve(path)
        let fileManager = FileManager.default

        if mode == "propose" {
            let rel = pathValidator.relativePath(for: url)
            try await PatchSetStore.shared.stageWrite(patchSetId: patchSetId, toolCallId: toolCallId, relativePath: rel, content: "")
            return "Proposed create file at \(rel) (patch_set_id=\(patchSetId))."
        }

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
                ],
                "mode": [
                    "type": "string",
                    "description": "One of: apply, propose. Default: apply.",
                    "enum": ["apply", "propose"]
                ],
                "patch_set_id": [
                    "type": "string",
                    "description": "Patch set identifier to stage into when mode=propose."
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

        let mode = (arguments["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "apply"
        let toolCallId = (arguments["_tool_call_id"] as? String) ?? UUID().uuidString
        let patchSetId = (arguments["patch_set_id"] as? String)
            ?? (arguments["_conversation_id"] as? String)
            ?? "default"

        let url = try pathValidator.validateAndResolve(path)

        if mode == "propose" {
            let rel = pathValidator.relativePath(for: url)
            try await PatchSetStore.shared.stageDelete(patchSetId: patchSetId, toolCallId: toolCallId, relativePath: rel)
            return "Proposed delete \(rel) (patch_set_id=\(patchSetId))."
        }
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
                "targetPath": [
                    "type": "string",
                    "description": "Deprecated alias for path. Use path instead."
                ],
                "old_text": [
                    "type": "string",
                    "description": "The exact text to find and replace. Must match exactly including whitespace."
                ],
                "new_text": [
                    "type": "string",
                    "description": "The new text to replace the old text with."
                ],
                "mode": [
                    "type": "string",
                    "description": "One of: apply, propose. Default: apply.",
                    "enum": ["apply", "propose"]
                ],
                "patch_set_id": [
                    "type": "string",
                    "description": "Patch set identifier to stage into when mode=propose."
                ]
            ],
            "required": ["path", "old_text", "new_text"]
        ]
    }
    
    let fileSystemService: FileSystemService
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol
    
    private func resolvedPath(from arguments: [String: Any]) throws -> String {
        let candidates: [Any?] = [
            arguments["path"],
            arguments["targetPath"],
            arguments["target_path"],
            arguments["file_path"],
            arguments["file"],
            arguments["target"],
        ]

        let path = candidates
            .compactMap { $0 as? String }
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        guard let path else {
            let keys = arguments.keys.sorted().joined(separator: ", ")
            throw AppError.aiServiceError(
                "Missing 'path' argument for replace_in_file. Provided keys: [\(keys)]. "
                    + "Fix: include a non-empty file path. Preferred key: 'path'. Accepted aliases: targetPath, target_path, file_path, file, target. Example:\n"
                    + "{\n  \"path\": \"src/App.css\",\n  \"old_text\": \".old { color: red; }\",\n  \"new_text\": \".old { color: blue; }\"\n}"
            )
        }
        
        return path
    }

    private func requiredString(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String else {
            let keys = arguments.keys.sorted().joined(separator: ", ")
            throw AppError.aiServiceError(
                "Missing '\(key)' argument for replace_in_file. Provided keys: [\(keys)]. "
                    + "Fix: include a non-empty '\(key)' value. Example:\n"
                    + "{\n  \"path\": \"src/App.css\",\n  \"\(key)\": \".old { color: blue; }\"\n}"
            )
        }
        return value
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let path = try resolvedPath(from: arguments)
        let oldText = try requiredString("old_text", in: arguments)
        let newText = try requiredString("new_text", in: arguments)

        let mode = (arguments["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "apply"
        let toolCallId = (arguments["_tool_call_id"] as? String) ?? UUID().uuidString
        let patchSetId = (arguments["patch_set_id"] as? String)
            ?? (arguments["_conversation_id"] as? String)
            ?? "default"
        
        let url = try pathValidator.validateAndResolve(path)
        let relativePath = pathValidator.relativePath(for: url)
        let content = try fileSystemService.readFile(at: url)
        
        if !content.contains(oldText) {
            return "Error: Could not find the specified old_text in the file. Make sure it matches exactly."
        }
        
        let newContent = content.replacingOccurrences(of: oldText, with: newText)

        if mode == "propose" {
            try await PatchSetStore.shared.stageWrite(
                patchSetId: patchSetId,
                toolCallId: toolCallId,
                relativePath: relativePath,
                content: newContent
            )
            await AIToolTraceLogger.shared.log(type: "fs.replace_in_file_proposed", data: [
                "path": relativePath,
                "patchSetId": patchSetId
            ])
            return "Proposed replace in \(relativePath) (patch_set_id=\(patchSetId))."
        }

        await AIToolTraceLogger.shared.log(type: "fs.replace_in_file", data: [
            "path": relativePath
        ])
        try fileSystemService.writeFile(content: newContent, to: url)
        Task { @MainActor in
            eventBus.publish(FileModifiedEvent(url: url))
        }
        
        return "Successfully replaced content in \(relativePath)"
    }
}
