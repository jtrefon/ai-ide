import Foundation

extension CodebaseIndex {
    public func searchIndexedText(pattern: String, limit: Int = 100) async throws -> [String] {
        let needle = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return [] }

        let boundedLimit = max(1, min(500, limit))

        let maxCandidateFiles = min(800, max(50, boundedLimit * 20))
        let candidatePaths = try await findCandidatePaths(needle: needle, maxCandidateFiles: maxCandidateFiles)
        return searchCandidatePaths(candidatePaths, needle: needle, boundedLimit: boundedLimit)
    }

    private func searchCandidatePaths(_ candidatePaths: [String], needle: String, boundedLimit: Int) -> [String] {
        if candidatePaths.isEmpty { return [] }

        var output: [String] = []
        output.reserveCapacity(min(boundedLimit, 50))

        for absPath in candidatePaths {
            if output.count >= boundedLimit { break }
            appendMatches(in: absPath, needle: needle, boundedLimit: boundedLimit, output: &output)
        }

        return output
    }

    private func appendMatches(in absPath: String, needle: String, boundedLimit: Int, output: inout [String]) {
        let fileURL = URL(fileURLWithPath: absPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() {
            if output.count >= boundedLimit { break }
            guard line.contains(needle) else { continue }

            output.append(makeMatchLine(absPath: absPath, lineNo: idx + 1, line: line))
        }
    }

    private func makeMatchLine(absPath: String, lineNo: Int, line: String) -> String {
        let snippetMax = 240
        let snippet = line.count > snippetMax ? String(line.prefix(snippetMax)) + "…" : line
        return "\(relativePath(absPath)):\(lineNo): \(snippet)"
    }

    private func findCandidatePaths(needle: String, maxCandidateFiles: Int) async throws -> [String] {
        let ftsQuery = makeFTSQuery(from: needle)
        if !ftsQuery.isEmpty {
            return (try? await database.candidatePathsForFTS(query: ftsQuery, limit: maxCandidateFiles)) ?? []
        }

        return (try? await database.listResourcePaths(matching: nil, limit: maxCandidateFiles, offset: 0)) ?? []
    }

    private func makeFTSQuery(from needle: String) -> String {
        let tokens = needle
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .map { String($0) }
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }

        return tokens.prefix(3).joined(separator: " AND ")
    }

    private func relativePath(_ absPath: String) -> String {
        if absPath.hasPrefix(projectRoot.path + "/") {
            return String(absPath.dropFirst(projectRoot.path.count + 1))
        }
        return absPath
    }
}
