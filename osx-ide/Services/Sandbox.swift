import Foundation

actor Sandbox {
    struct Policy: Sendable {
        let allowedCapabilities: ToolCapabilities
        let blockedPathPatterns: [String]
        let requireReadBeforeWrite: Bool
        let projectRoot: URL

        static func `default`(projectRoot: URL) -> Policy {
            Policy(allowedCapabilities: [.fileRead, .fileWrite, .fileDelete, .fileSearch, .directoryList, .indexSearch, .webSearch, .webBrowse],
                   blockedPathPatterns: [".git/**", "node_modules/**", ".build/**"],
                   requireReadBeforeWrite: true,
                   projectRoot: projectRoot)
        }

        static func readOnly(projectRoot: URL) -> Policy {
            Policy(allowedCapabilities: [.fileRead, .fileSearch, .directoryList, .indexSearch, .webSearch, .webBrowse],
                   blockedPathPatterns: ["**"],
                   requireReadBeforeWrite: false,
                   projectRoot: projectRoot)
        }
    }

    private let policy: Policy
    private var readPaths: [String: Set<String>] = [:] // conversationId → Set of relative paths

    init(policy: Policy) {
        self.policy = policy
    }

    // MARK: - Authorization

    func authorize(capability: ToolCapabilities) throws {
        guard policy.allowedCapabilities.contains(capability) else {
            throw SandboxError.unauthorized(capability: capability)
        }
    }

    func resolvePath(_ path: String) throws -> URL {
        let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        if cleaned.hasPrefix("/") {
            url = URL(fileURLWithPath: cleaned)
        } else {
            url = policy.projectRoot.appendingPathComponent(cleaned)
        }
        let standardized = url.standardizedFileURL
        guard standardized.path.hasPrefix(policy.projectRoot.standardizedFileURL.path) else {
            throw SandboxError.pathOutsideRoot(path: cleaned)
        }
        for pattern in policy.blockedPathPatterns {
            if matchGlob(pattern: pattern, path: standardized.path) {
                throw SandboxError.pathBlocked(path: cleaned, pattern: pattern)
            }
        }
        return standardized
    }

    func relativePath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let standardized = url.standardizedFileURL.path
        let root = policy.projectRoot.standardizedFileURL.path
        if standardized.hasPrefix(root + "/") {
            return String(standardized.dropFirst(root.count + 1))
        }
        if standardized == root {
            return "."
        }
        return standardized
    }

    // MARK: - Read-Before-Write

    func recordRead(path: URL, conversationId: String?) {
        let key = conversationId ?? "_default"
        let relPath = relativePath(path.path)
        readPaths[key, default: []].insert(relPath)
    }

    func hasRead(path: URL, conversationId: String?) -> Bool {
        let key = conversationId ?? "_default"
        let relPath = relativePath(path.path)
        return readPaths[key]?.contains(relPath) ?? false
    }

    func resetReads(conversationId: String?) {
        let key = conversationId ?? "_default"
        readPaths[key] = []
    }

    func authorizeWrite(path: URL, conversationId: String?) throws {
        guard !policy.requireReadBeforeWrite || hasRead(path: path, conversationId: conversationId) else {
            throw SandboxError.mustReadFirst(path: relativePath(path.path))
        }
    }

    // MARK: - Duplicate Detection

    func checkDuplicate(content: String, at path: URL) -> Bool {
        guard let existing = try? String(contentsOf: path, encoding: .utf8) else { return false }
        return existing.trimmingCharacters(in: .whitespacesAndNewlines) == content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Glob Matching

    private func matchGlob(pattern: String, path: String) -> Bool {
        guard let regex = try? globToRegex(pattern) else { return false }
        return path.range(of: regex, options: .regularExpression) != nil
    }

    private func globToRegex(_ pattern: String) throws -> String {
        var regex = "^"
        for char in pattern {
            switch char {
            case "*": regex += ".*"
            case "?": regex += "."
            case ".": regex += "\\."
            default: regex += String(char)
            }
        }
        regex += "$"
        return regex
    }
}

enum SandboxError: LocalizedError, Sendable {
    case unauthorized(capability: ToolCapabilities)
    case pathOutsideRoot(path: String)
    case pathBlocked(path: String, pattern: String)
    case mustReadFirst(path: String)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let caps): return "Capability not allowed: \(caps)"
        case .pathOutsideRoot(let p): return "Path outside project root: \(p)"
        case .pathBlocked(let p, let pat): return "Path blocked by pattern '\(pat)': \(p)"
        case .mustReadFirst(let p): return "Must read \(p) before writing"
        }
    }
}
