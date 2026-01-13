//
//  ProjectTools.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation

struct GetProjectStructureTool: AITool {
    let name = "get_project_structure"
    let description = "Get the complete file and folder structure of the current project. Returns a hierarchical tree view of all files and directories. Use this to understand the project layout and cognitively identify files even with partial or misspelled names."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "max_depth": [
                    "type": "integer",
                    "description": "Maximum depth to traverse (default: unlimited). " +
                    "Use 2-3 for overview, unlimited for complete structure."
                ]
            ],
            "required": []
        ]
    }
    
    let projectRoot: URL
    
    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let maxDepth = arguments["max_depth"] as? Int else {
            throw AppError.aiServiceError("Missing 'max_depth' argument for get_project_structure")
        }
        return buildTreeSync(maxDepth: maxDepth)
    }
    
    private func buildTreeSync(maxDepth: Int?) -> String {
        var result = "Project Structure: \(projectRoot.lastPathComponent)/\n"
        result += buildTree(at: projectRoot, prefix: "", depth: 0, maxDepth: maxDepth)
        return result
    }
    
    private func buildTree(at url: URL, prefix: String, depth: Int, maxDepth: Int?) -> String {
        if let maxDepth = maxDepth, depth >= maxDepth {
            return ""
        }
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) else {
            return ""
        }
        
        var output = ""
        for (index, item) in contents.enumerated() {
            let isLast = index == contents.count - 1
            let connector = isLast ? "└── " : "├── "
            let childPrefix = prefix + (isLast ? "    " : "│   ")
            
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let displayName = isDirectory ? item.lastPathComponent + "/" : item.lastPathComponent
            
            output += prefix + connector + displayName + "\n"
            
            if isDirectory {
                output += buildTree(at: item, prefix: childPrefix, depth: depth + 1, maxDepth: maxDepth)
            }
        }
        
        return output
    }
}

struct ListAllFilesTool: AITool {
    let name = "list_all_files"
    let description = "Get a flat list of ALL files in the project with their relative paths. Use this when you need to find a specific file by name (even partial or misspelled). You can cognitively search through this list to identify the correct file."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [:],
            "required": []
        ]
    }
    
    let projectRoot: URL

    func execute(arguments: ToolArguments) async throws -> String {
        return getFilesSync()
    }
    
    private func getFilesSync() -> String {
        let files = getAllFiles(at: projectRoot, relativeTo: projectRoot)
        
        if files.isEmpty {
            return "No files found in project."
        }
        
        let fileCount = files.count
        var result = "Project: \(projectRoot.lastPathComponent) (\(fileCount) files)\n\n"
        result += files.joined(separator: "\n")
        
        return result
    }
    
    private func getAllFiles(at url: URL, relativeTo root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        var files: [String] = []
        
        for case let fileURL as URL in enumerator {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDirectory {
                let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                files.append(relativePath)
            }
        }
        
        return files.sorted()
    }
}

struct FindFileRegexTool: AITool {
    let name = "find_file_regex"
    let description = "FALLBACK TOOL: Use only when list_all_files returns too many files (>1000) and you cannot cognitively search. Searches for files matching a regex pattern. Much less intelligent than cognitive search - use as last resort."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "Regex pattern to match against file names (e.g., 'train.*\\.py' for train_cli.py)"
                ]
            ],
            "required": ["pattern"]
        ]
    }
    
    let projectRoot: URL
    
    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let pattern = arguments["pattern"] as? String else {
            throw AppError.aiServiceError("Missing 'pattern' argument for find_file_regex")
        }
        return try findFilesSync(pattern: pattern)
    }
    
    private func findFilesSync(pattern: String) throws -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            throw AppError.aiServiceError("Invalid regex pattern: \(pattern)")
        }
        
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "No files found."
        }
        
        var matches: [String] = []
        
        for case let fileURL as URL in enumerator {
            if !isFile(fileURL: fileURL) {
                continue
            }
            
            let fileName = fileURL.lastPathComponent
            let range = NSRange(location: 0, length: fileName.utf16.count)
            
            if regex.firstMatch(in: fileName, options: [], range: range) != nil {
                let relativePath = fileURL.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
                matches.append(relativePath)
            }
        }
        
        if matches.isEmpty {
            return "No files matching pattern '\(pattern)' found."
        }
        
        return "Found \(matches.count) file(s):\n" + matches.joined(separator: "\n")
    }
    
    private func isFile(fileURL: URL) -> Bool {
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            return resourceValues.isRegularFile ?? false
        } catch {
            return false
        }
    }
}
