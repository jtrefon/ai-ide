import Foundation

extension CodebaseIndex {
    public func listIndexedFiles(matching query: String?, limit: Int = 50, offset: Int = 0) async throws -> [String] {
        let absPaths = try await database.listResourcePaths(matching: query, limit: limit, offset: offset)
        return absPaths.map { absPath in
            if absPath.hasPrefix(projectRoot.path + "/") {
                return String(absPath.dropFirst(projectRoot.path.count + 1))
            }
            return absPath
        }
    }
}
