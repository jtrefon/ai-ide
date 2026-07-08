import Foundation

// MARK: - Legacy v1 Protocol

public struct ToolArguments: @unchecked Sendable {
    public let raw: [String: Any]
    public init(_ raw: [String: Any]) {
        self.raw = raw
    }
}

public protocol AITool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [String: Any] { get }
    func execute(arguments: ToolArguments) async throws -> String
}

// MARK: - Unified Tool Protocol (replaces AITool + ToolDefinition)

protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var schema: JSONSchema { get }
    var capabilities: ToolCapabilities { get }
    var sideEffects: ToolSideEffect { get }
    var isolation: ToolIsolation { get }
    var timeout: TimeInterval { get }
    func execute(_ request: ToolExecutionRequest) async throws -> ToolFeedback
}

// MARK: - Capabilities & Side Effects

struct ToolCapabilities: OptionSet, Sendable, Codable {
    let rawValue: UInt16
    static let fileRead = ToolCapabilities(rawValue: 1 << 0)
    static let fileWrite = ToolCapabilities(rawValue: 1 << 1)
    static let fileDelete = ToolCapabilities(rawValue: 1 << 2)
    static let fileSearch = ToolCapabilities(rawValue: 1 << 3)
    static let directoryList = ToolCapabilities(rawValue: 1 << 4)
    static let indexSearch = ToolCapabilities(rawValue: 1 << 5)
    static let webSearch = ToolCapabilities(rawValue: 1 << 6)
    static let webBrowse = ToolCapabilities(rawValue: 1 << 7)
    static let commandExecution = ToolCapabilities(rawValue: 1 << 8)
    static let projectStructure = ToolCapabilities(rawValue: 1 << 9)
}

struct ToolSideEffect: OptionSet, Sendable, Codable {
    let rawValue: UInt16
    static let readsFile = ToolSideEffect(rawValue: 1 << 0)
    static let writesFile = ToolSideEffect(rawValue: 1 << 1)
    static let deletesFile = ToolSideEffect(rawValue: 1 << 2)
    static let modifiesFile = ToolSideEffect(rawValue: 1 << 3)
    static let executesCommand = ToolSideEffect(rawValue: 1 << 4)
    static let makesNetworkRequest = ToolSideEffect(rawValue: 1 << 5)
}

// MARK: - Isolation Model

enum ToolIsolation: String, Sendable, Codable {
    case concurrent
    case pathIsolated
    case sessionIsolated
    case globallySerial
}

// MARK: - JSON Schema

indirect enum JSONSchema: Sendable, Codable {
    case object(properties: [String: JSONSchema], required: [String])
    case array(items: JSONSchema)
    case string(description: String?, enumValues: [String]?)
    case integer(description: String?)
    case number(description: String?)
    case boolean(description: String?)
    case any

    func toDictionary() -> [String: Any] {
        switch self {
        case .object(let props, let req):
            var dict: [String: Any] = ["type": "object"]
            dict["properties"] = props.mapValues { $0.toDictionary() }
            if !req.isEmpty { dict["required"] = req }; return dict
        case .array(let item):
            return ["type": "array", "items": item.toDictionary()]
        case .string(let desc, let vals):
            var dict: [String: Any] = ["type": "string"]
            if let d = desc { dict["description"] = d }
            if let v = vals, !v.isEmpty { dict["enum"] = v }; return dict
        case .integer(let desc): return valueDict("integer", desc: desc)
        case .number(let desc): return valueDict("number", desc: desc)
        case .boolean(let desc): return valueDict("boolean", desc: desc)
        case .any: return [:]
        }
    }
    private func valueDict(_ type: String, desc: String?) -> [String: Any] {
        var dict = ["type": type]; if let d = desc { dict["description"] = d }; return dict
    }
}

// MARK: - Tool Value

enum ToolValue: Sendable, Codable {
    case string(String), integer(Int), number(Double), boolean(Bool), array([ToolValue]), dictionary([String: ToolValue])
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    static func from(dictionary: [String: Any]) -> [String: ToolValue] { dictionary.mapValues { from(any: $0) } }
    static func from(any value: Any) -> ToolValue {
        switch value {
        case let v as String: return .string(v)
        case let v as Int: return .integer(v)
        case let v as Double: return .number(v)
        case let v as Bool: return .boolean(v)
        case let v as [Any]: return .array(v.map { from(any: $0) })
        case let v as [String: Any]: return .dictionary(v.mapValues { from(any: $0) })
        default: return .string("\(value)")
        }
    }
}

// MARK: - Execution Request

struct ToolExecutionRequest: Sendable {
    let toolName: String
    let arguments: [String: ToolValue]
    let context: ExecutionContext
    func requiredString(_ key: String) throws -> String {
        guard case .string(let v)? = arguments[key], !v.isEmpty else { throw ToolExecutionError.missingArgument(key) }
        return v
    }
    func optionalInt(_ key: String) -> Int? {
        guard case .integer(let v)? = arguments[key] else { return nil }
        return v
    }
}

struct ExecutionContext: Sendable {
    let conversationId: String
    let turnId: String
    let projectRoot: URL
    let allowedCapabilities: ToolCapabilities
    let sandbox: SandboxConfiguration

    static func coder(conversationId: String, turnId: String, projectRoot: URL) -> ExecutionContext {
        ExecutionContext(conversationId: conversationId, turnId: turnId, projectRoot: projectRoot,
                         allowedCapabilities: [.fileRead, .fileWrite, .fileDelete, .fileSearch, .directoryList, .indexSearch, .webSearch, .webBrowse],
                         sandbox: .coder)
    }
}

struct SandboxConfiguration: Sendable {
    var enforceReadBeforeWrite = true
    var blockedPathPatterns: [String] = [".git/**", "node_modules/**"]
    static let coder = SandboxConfiguration(enforceReadBeforeWrite: true, blockedPathPatterns: [".git/**", "node_modules/**", ".build/**"])
    static let readOnly = SandboxConfiguration(enforceReadBeforeWrite: false, blockedPathPatterns: ["**"])
}

// MARK: - Tool Feedback

enum ToolFeedbackStatus: String, Sendable, Codable { case success, error, partial }

struct ToolFeedback: Sendable, Codable {
    let status: ToolFeedbackStatus
    let message: String
    let content: ToolContent?
    let error: ToolErrorInfo?

    static func success(_ m: String) -> ToolFeedback { ToolFeedback(status: .success, message: m, content: nil, error: nil) }
    static func success(_ m: String, text: String, metadata: [String: String]? = nil) -> ToolFeedback {
        ToolFeedback(status: .success, message: m, content: ToolContent(data: .text(text), metadata: metadata), error: nil)
    }
    static func success(_ m: String, items: [ToolContentItem], metadata: [String: String]? = nil) -> ToolFeedback {
        ToolFeedback(status: .success, message: m, content: ToolContent(data: .items(items), metadata: metadata), error: nil)
    }
    static func error(_ m: String, code: String, recoverable: Bool = true, alternatives: [ToolAlternative]? = nil) -> ToolFeedback {
        ToolFeedback(status: .error, message: m, content: nil, error: ToolErrorInfo(code: code, message: m, recoverable: recoverable, alternatives: alternatives))
    }
    static func mustReadFirst(_ path: String) -> ToolFeedback {
        ToolFeedback.error("Read \(path) first.", code: "MUTATION_WITHOUT_PRIOR_READ",
                          alternatives: [ToolAlternative(description: "Read the file", toolName: "read_file", arguments: ["path": path])])
    }
}

struct ToolContent: Sendable, Codable { let data: ToolContentData; let metadata: [String: String]? }
enum ToolContentData: Sendable, Codable { case text(String), items([ToolContentItem]), empty }
struct ToolContentItem: Sendable, Codable { let label: String; let description: String?; let path: String?; let lineNumber: Int?; let kind: String? }
struct ToolErrorInfo: Sendable, Codable { let code: String; let message: String; let recoverable: Bool; let alternatives: [ToolAlternative]? }

struct ToolAlternative: Sendable, Codable {
    let description: String; let suggestion: String?; let toolName: String?; let arguments: [String: String]?
    init(description: String, suggestion: String? = nil, toolName: String? = nil, arguments: [String: String]? = nil) {
        self.description = description; self.suggestion = suggestion; self.toolName = toolName; self.arguments = arguments
    }
}

// MARK: - Formatter

struct ToolFeedbackFormatter {
    func format(_ fb: ToolFeedback) -> String {
        var lines: [String] = ["status: \(fb.status.rawValue)", "message: \(fb.message)"]
        if let c = fb.content {
            switch c.data {
            case .text(let t):
                lines.append("content:")
                for line in t.split(separator: "\n", maxSplits: 500, omittingEmptySubsequences: false) { lines.append("  \(line)") }
                if let m = c.metadata { for (k, v) in m { lines.append("  [\(k): \(v)]") } }
            case .items(let items):
                for item in items {
                    var l = "  - \(item.label)"; if let k = item.kind { l += " (\(k))" }; lines.append(l)
                    if let d = item.description { lines.append("    \(d)") }
                    if let p = item.path { lines.append("    path: \(p)") }
                    if let ln = item.lineNumber { lines.append("    line: \(ln)") }
                }
            case .empty: break
            }
        }
        if let e = fb.error {
            lines.append("error_code: \(e.code)"); lines.append("recoverable: \(e.recoverable)")
            if let alts = e.alternatives { for a in alts { lines.append("  try: \(a.description)"); if let t = a.toolName { lines.append("  tool: \(t)") } } }
        }
        return lines.joined(separator: "\n")
    }
    func formatBatch(_ fbs: [ToolFeedback]) -> String {
        fbs.enumerated().map { i, fb in "result_\(i + 1):\n" + format(fb).split(separator: "\n").map { "  " + $0 }.joined(separator: "\n") }.joined(separator: "\n\n")
    }
}

// MARK: - Legacy v2 transitional types

struct PromptMaterial: Sendable, Codable { let concise: String; let standard: String; let comprehensive: String; let successCriteria: String?; let guidance: ToolGuidance? }
struct ToolGuidance: Sendable, Codable { let whenToUse: String; let whenNotToUse: String?; let bestPractices: [String]? }
struct ErrorCodeDocumentation: Sendable, Codable { let code: String; let meaning: String; let recommendedAction: String; let alternativeTool: String? }

// MARK: - Errors

enum ToolExecutionError: LocalizedError, Sendable {
    case missingArgument(String), notFound(String), sandboxViolation(String), executionFailed(String)
    var errorDescription: String? {
        switch self {
        case .missingArgument(let k): return "Missing required argument: \(k)"
        case .notFound(let n): return "Tool not found: \(n)"
        case .sandboxViolation(let m): return "Sandbox violation: \(m)"
        case .executionFailed(let m): return "Tool execution failed: \(m)"
        }
    }
}

// MARK: - ToolAdapter (bridges old AITool to new Tool protocol)

struct ToolAdapter: Tool {
    let name: String
    let description: String
    let schema: JSONSchema
    let capabilities: ToolCapabilities
    let sideEffects: ToolSideEffect
    let isolation: ToolIsolation
    let timeout: TimeInterval
    let wrapped: any AITool

    func execute(_ request: ToolExecutionRequest) async throws -> ToolFeedback {
        var raw: [String: Any] = [:]
        for (key, value) in request.arguments {
            switch value {
            case .string(let v): raw[key] = v
            case .integer(let v): raw[key] = v
            case .number(let v): raw[key] = v
            case .boolean(let v): raw[key] = v
            default: break
            }
        }
        let args = ToolArguments(raw)
        let result = try await wrapped.execute(arguments: args)
        return ToolFeedback.success(result)
    }
}
