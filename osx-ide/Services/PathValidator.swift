//
//  PathValidator.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation

struct PathValidator {
    let projectRoot: URL

    private var standardizedProjectRoot: URL {
        projectRoot.standardizedFileURL
    }

    private func isWithinProjectRoot(_ url: URL) -> Bool {
        let resolvedURL = url.standardizedFileURL
        let rootURL = standardizedProjectRoot
        let resolvedPathComponents = resolvedURL.pathComponents
        let rootPathComponents = rootURL.pathComponents

        guard resolvedPathComponents.count >= rootPathComponents.count else {
            return false
        }

        return Array(resolvedPathComponents.prefix(rootPathComponents.count)) == rootPathComponents
    }

    private func normalizePseudoRootPath(_ path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return path }

        if trimmedPath == "/project" || trimmedPath == "project" {
            return "."
        }

        if trimmedPath.hasPrefix("/project/") {
            return String(trimmedPath.dropFirst("/project/".count))
        }

        if trimmedPath.hasPrefix("project/") {
            return String(trimmedPath.dropFirst("project/".count))
        }

        return trimmedPath
    }

    /// Validates and resolves a path, ensuring it's within the project root
    func validateAndResolve(_ path: String) throws -> URL {
        let normalizedPath = normalizePseudoRootPath(path)
        let url: URL

        // Handle absolute vs relative paths
        if normalizedPath.hasPrefix("/") {
            // If the absolute path is already within the project root, use it as is
            let candidateURL = URL(fileURLWithPath: normalizedPath).standardizedFileURL
            if isWithinProjectRoot(candidateURL) {
                url = candidateURL
            } else {
                // Otherwise, strip the leading slash and treat it as relative to project root
                let relativePath = String(normalizedPath.dropFirst())
                url = projectRoot.appendingPathComponent(relativePath)
            }
        } else {
            url = projectRoot.appendingPathComponent(normalizedPath)
        }

        // Resolve to canonical path
        let resolvedURL = url.standardizedFileURL

        // Ensure the resolved path is within project root (sandboxing)
        guard isWithinProjectRoot(resolvedURL) else {
            throw AppError.aiServiceError("Access denied: '\(path)' is outside the project directory. All file operations are sandboxed to: \(projectRoot.path)")
        }

        return resolvedURL
    }

    /// Get relative path from project root
    func relativePath(for url: URL) -> String {
        let absolutePath = url.standardizedFileURL.path
        let rootPath = standardizedProjectRoot.path

        if absolutePath.hasPrefix(rootPath + "/") {
            return String(absolutePath.dropFirst(rootPath.count + 1))
        } else if absolutePath == rootPath {
            return "."
        } else {
            return absolutePath
        }
    }
}
