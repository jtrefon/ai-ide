import Foundation

enum ToolCapability: String, Sendable, Codable, CaseIterable {
    case fileRead, fileWrite, fileDelete, fileSearch, directoryList
    case indexSearch, indexSemantic, indexMemory, webSearch, webBrowse
    case commandExecution, projectStructure, memoryManagement
}

struct ToolSideEffect: OptionSet, Sendable, Codable {
    let rawValue: UInt16
    static let readsFile = ToolSideEffect(rawValue: 1 << 0)
    static let writesFile = ToolSideEffect(rawValue: 1 << 1)
    static let deletesFile = ToolSideEffect(rawValue: 1 << 2)
    static let modifiesFile = ToolSideEffect(rawValue: 1 << 3)
    static let executesCommand = ToolSideEffect(rawValue: 1 << 4)
    static let makesNetworkRequest = ToolSideEffect(rawValue: 1 << 5)
    static let none = ToolSideEffect(rawValue: 0)
}

enum ToolIsolation: String, Sendable, Codable { case concurrent, pathIsolated, sessionIsolated, globallySerial }

indirect enum JSONSchema: Sendable, Codable {
    case object(properties: [String: JSONSchema], required: [String])
    case array(items: JSONSchema)
    case string(description: String?, enumValues: [String]?)
    case integer(desc: String?), number(desc: String?), boolean(desc: String?)
    case any
    func toDict() -> [String: Any] {
        switch self {
        case .object(properties: let props, required: let req):
            var dict: [String: Any] = ["type": "object"]
            dict["properties"] = props.mapValues { $0.toDict() }
            if !req.isEmpty { dict["required"] = req }
            return dict
        case .array(items: let item):
            return ["type": "array", "items": item.toDict()]
        case .string(description: let desc, enumValues: let vals):
            var dict: [String: Any] = ["type": "string"]
            if let d = desc { dict["description"] = d }
            if let v = vals, !v.isEmpty { dict["enum"] = v }
            return dict
        case .integer(desc: let desc):
            var dict: [String: Any] = ["type": "integer"]
            if let d = desc { dict["description"] = d }
            return dict
        case .number(desc: let desc):
            var dict: [String: Any] = ["type": "number"]
            if let d = desc { dict["description"] = d }
            return dict
        case .boolean(desc: let desc):
            var dict: [String: Any] = ["type": "boolean"]
            if let d = desc { dict["description"] = d }
            return dict
        case .any:
            return [:]
        }
    }
}

struct PromptMaterial: Sendable, Codable {
    let concise: String; let standard: String; let comprehensive: String
    let successCriteria: String?; let guidance: ToolGuidance?
}

struct ToolGuidance: Sendable, Codable {
    let whenToUse: String; let whenNotToUse: String?; let bestPractices: [String]?
}

struct ErrorCodeDocumentation: Sendable, Codable {
    let code: String; let meaning: String; let recommendedAction: String; let alternativeTool: String?
}

struct ExecutionContext: Sendable {
    let conversationId: String; let turnId: String; let projectRoot: URL
    let mode: AgentMode; let allowedCapabilities: Set<ToolCapability>; let sandbox: SandboxConfiguration
    static func coder(cid: String, tid: String, root: URL) -> ExecutionContext {
        ExecutionContext(conversationId: cid, turnId: tid, projectRoot: root, mode: .coder,
                         allowedCapabilities: ModeConfiguration.coder.allowedCapabilities, sandbox: .coder)
    }
}

struct ToolExecutionRequest: Sendable {
    let toolName: String; let arguments: [String: ToolValue]; let context: ExecutionContext
    func requiredString(_ key: String) throws -> String {
        guard case .string(let v)? = arguments[key], !v.isEmpty else { throw ToolExecError.missing(key) }
        return v
    }
    func optionalInt(_ key: String) -> Int? {
        guard case .integer(let v)? = arguments[key] else { return nil }
        return v
    }
}

enum ToolValue: Sendable, Codable {
    case string(String), integer(Int), number(Double), boolean(Bool), array([ToolValue]), dictionary([String: ToolValue])
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    static func from(dict: [String: Any]) -> [String: ToolValue] { dict.mapValues { from(j: $0) } }
    static func from(j: Any) -> ToolValue {
        switch j {
        case let v as String: return .string(v); case let v as Int: return .integer(v)
        case let v as Double: return .number(v); case let v as Bool: return .boolean(v)
        case let v as [Any]: return .array(v.map { from(j: $0) })
        case let v as [String: Any]: return .dictionary(v.mapValues { from(j: $0) })
        default: return .string("\(j)")
        }
    }
}

enum ToolExecError: LocalizedError, Sendable {
    case missing(String)
    var errorDescription: String? {
        switch self { case .missing(let k): return "Missing arg: " + k }
    }
}

struct ToolDefinition: Sendable {
    let name: String; let description: String; let parameters: JSONSchema
    let capabilities: Set<ToolCapability>; let sideEffects: ToolSideEffect
    let allowedModes: Set<AgentMode>; let isolation: ToolIsolation
    let promptMaterial: PromptMaterial; let errorCodes: [ErrorCodeDocumentation]
    let defaultTimeout: TimeInterval
    let execute: @Sendable (ToolExecutionRequest) async throws -> ToolFeedback

    static func command(
        name: String, desc: String, params: JSONSchema, caps: Set<ToolCapability>,
        se: ToolSideEffect, pm: PromptMaterial, errorCodes: [ErrorCodeDocumentation] = [],
        exec: @escaping @Sendable (ToolExecutionRequest) async throws -> ToolFeedback
    ) -> ToolDefinition {
        ToolDefinition(name: name, description: desc, parameters: params, capabilities: caps,
                       sideEffects: se, allowedModes: [.coder, .agent], isolation: .pathIsolated,
                       promptMaterial: pm, errorCodes: errorCodes, defaultTimeout: 30, execute: exec)
    }

    static func query(
        name: String, desc: String, params: JSONSchema, caps: Set<ToolCapability>,
        se: ToolSideEffect = .none, cf: String, pm: PromptMaterial,
        errorCodes: [ErrorCodeDocumentation] = [],
        exec: @escaping @Sendable (ToolExecutionRequest) async throws -> ToolFeedback
    ) -> ToolDefinition {
        ToolDefinition(name: name, description: desc, parameters: params, capabilities: caps,
                       sideEffects: se.union(.readsFile), allowedModes: [.coder, .agent], isolation: .concurrent,
                       promptMaterial: pm, errorCodes: errorCodes, defaultTimeout: 30, execute: exec)
    }
}

struct SandboxConfiguration: Sendable {
    var enforceReadBeforeWrite = true; var blockedPathPatterns = [".git/**", "node_modules/**"]
    static let coder = SandboxConfiguration(enforceReadBeforeWrite: true, blockedPathPatterns: [".git/**", "node_modules/**", ".build/**"])
    static let readOnly = SandboxConfiguration(enforceReadBeforeWrite: false, blockedPathPatterns: ["**"])
}

struct ModeConfiguration: Sendable {
    let allowedCapabilities: Set<ToolCapability>; let sandbox: SandboxConfiguration
    static let coder = ModeConfiguration(allowedCapabilities: [.fileRead, .fileWrite, .fileDelete, .fileSearch, .directoryList, .indexSearch, .indexSemantic, .indexMemory, .webSearch, .webBrowse], sandbox: .coder)
}
