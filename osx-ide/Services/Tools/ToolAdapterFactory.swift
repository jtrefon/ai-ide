import Foundation

enum ToolAdapterFactory {
    static func adapt(_ tool: any AITool) -> Tool {
        ToolAdapter(
            name: tool.name,
            description: tool.description,
            schema: schemaFrom(parameters: tool.parameters),
            capabilities: capabilitiesFor(tool.name),
            sideEffects: sideEffectsFor(tool.name),
            isolation: isolationFor(tool.name),
            timeout: timeoutFor(tool.name),
            wrapped: tool
        )
    }

    static func adaptAll(_ tools: [any AITool]) -> [Tool] {
        tools.map { adapt($0) }
    }

    // MARK: - Capabilities

    private static func capabilitiesFor(_ name: String) -> ToolCapabilities {
        switch name {
        case "read_file", "view_file": return [.fileRead]
        case "write_file", "write_files", "create_file": return [.fileWrite]
        case "delete_file": return [.fileDelete]
        case "replace_in_file", "patch_file": return [.fileWrite]
        case "find_file", "find_by_name": return [.fileSearch]
        case "list_files", "list_dir", "list_directory", "get_project_structure": return [.directoryList]
        case "grep", "grep_search", "search_project", "find": return [.fileSearch, .indexSearch]
        case "web_search", "google": return [.webSearch]
        case "web_browse", "browse": return [.webBrowse]
        case "run_command", "run_shell", "bash": return [.commandExecution]
        case "inspect_symbol", "locate_symbol", "where_symbol": return [.indexSearch]
        default: return [.fileRead]
        }
    }

    private static func sideEffectsFor(_ name: String) -> ToolSideEffect {
        switch name {
        case "read_file", "view_file", "find_file", "list_files", "grep", "search_project",
             "find", "inspect_symbol", "locate_symbol", "where_symbol", "get_project_structure":
            return [.readsFile]
        case "write_file", "write_files", "create_file", "replace_in_file", "delete_file", "patch_file":
            return [.writesFile, .readsFile]
        case "run_command", "run_shell", "bash":
            return [.executesCommand]
        case "web_search", "google", "web_browse", "browse":
            return [.makesNetworkRequest]
        default:
            return []
        }
    }

    private static func isolationFor(_ name: String) -> ToolIsolation {
        switch name {
        case "write_file", "write_files", "create_file", "delete_file", "replace_in_file", "patch_file":
            return .pathIsolated
        case "run_command", "run_shell", "bash":
            return .sessionIsolated
        case "web_browse", "browse":
            return .sessionIsolated
        default:
            return .concurrent
        }
    }

    private static func timeoutFor(_ name: String) -> TimeInterval {
        switch name {
        case "run_command", "run_shell", "bash": return 120
        case "web_search", "google", "web_browse", "browse": return 35
        case "search_project", "find": return 30
        default: return 30
        }
    }

    // MARK: - Schema Conversion

    private static func schemaFrom(parameters: [String: Any]) -> JSONSchema {
        guard let type = parameters["type"] as? String else { return .any }
        switch type {
        case "object":
            let props = (parameters["properties"] as? [String: [String: Any]]) ?? [:]
            let required = (parameters["required"] as? [String]) ?? []
            return .object(
                properties: props.mapValues { schemaFrom(parameter: $0) },
                required: required
            )
        default:
            return .any
        }
    }

    private static func schemaFrom(parameter: [String: Any]) -> JSONSchema {
        guard let type = parameter["type"] as? String else { return .any }
        switch type {
        case "string":
            return .string(description: parameter["description"] as? String,
                          enumValues: parameter["enum"] as? [String])
        case "integer":
            return .integer(description: parameter["description"] as? String)
        case "number":
            return .number(description: parameter["description"] as? String)
        case "boolean":
            return .boolean(description: parameter["description"] as? String)
        case "array":
            return .array(items: .any)
        case "object":
            return .object(properties: [:], required: [])
        default:
            return .any
        }
    }
}
