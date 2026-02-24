//
//  PathValidator.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation

struct PathValidator {
    let projectRoot: URL

    /// Validates and resolves a path, ensuring it's within the project root
    func validateAndResolve(_ path: String) throws -> URL {
        let url: URL

        // Handle absolute vs relative paths
        if path.hasPrefix("/") {
            // If the absolute path is already within the project root, use it as is
            let candidateURL = URL(fileURLWithPath: path).standardized
            if candidateURL.path.hasPrefix(projectRoot.standardized.path) {
                url = candidateURL
            } else {
                // Otherwise, strip the leading slash and treat it as relative to project root
                let relativePath = String(path.dropFirst())
                url = projectRoot.appendingPathComponent(relativePath)
            }
        } else {
            url = projectRoot.appendingPathComponent(path)
        }

        // Resolve to canonical path
        let resolvedURL = url.standardized
        let resolvedPath = resolvedURL.path
        let rootPath = projectRoot.standardized.path

        // Ensure the resolved path is within project root (sandboxing)
        guard resolvedPath.hasPrefix(rootPath) else {
            throw AppError.aiServiceError("Access denied: '\(path)' is outside the project directory. All file operations are sandboxed to: \(projectRoot.path)")
        }

        return resolvedURL
    }

    /// Get relative path from project root
    func relativePath(for url: URL) -> String {
        let absolutePath = url.standardized.path
        let rootPath = projectRoot.standardized.path

        if absolutePath.hasPrefix(rootPath + "/") {
            return String(absolutePath.dropFirst(rootPath.count + 1))
        } else if absolutePath == rootPath {
            return "."
        } else {
            return absolutePath
        }
    }
}
