//
//  IndexExcludePatternManager.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import Foundation

/// Manages exclude patterns for indexing
struct IndexExcludePatternManager {

    // MARK: - Public Methods

    /// Loads exclude patterns from project configuration
    static func loadExcludePatterns(projectRoot: URL, defaultPatterns: [String]) -> [String] {
        let fileManager = FileManager.default
        let ideDir = projectRoot.appendingPathComponent(".ide", isDirectory: true)
        let excludeFile = ideDir.appendingPathComponent("index_exclude", isDirectory: false)

        do {
            try fileManager.createDirectory(at: ideDir, withIntermediateDirectories: true)
        } catch {
            return defaultPatterns
        }

        if !fileManager.fileExists(atPath: excludeFile.path) {
            let content = defaultExcludeFileContent(defaultPatterns: defaultPatterns)
            do {
                try content.write(to: excludeFile, atomically: true, encoding: .utf8)
            } catch {
                return defaultPatterns
            }
        }

        do {
            let raw = try String(contentsOf: excludeFile, encoding: .utf8)
            let custom = parseExcludeFile(raw)
            return mergeExcludePatterns(defaultPatterns: defaultPatterns, customPatterns: custom)
        } catch {
            return defaultPatterns
        }
    }

    // MARK: - Private Methods

    private static func parseExcludeFile(_ content: String) -> [String] {
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("#") }
    }

    private static func mergeExcludePatterns(defaultPatterns: [String], customPatterns: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        merged.reserveCapacity(defaultPatterns.count + customPatterns.count)

        for p in defaultPatterns + customPatterns {
            let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                merged.append(trimmed)
            }
        }
        return merged
    }

    private static func defaultExcludeFileContent(defaultPatterns: [String]) -> String {
        let header = """
# One pattern per line.
# Lines beginning with '#' are comments.
# Matching is path-based and intentionally simple; use directory names like 'node_modules' to exclude anywhere.

"""
        return header + defaultPatterns.joined(separator: "\n") + "\n"
    }
}
