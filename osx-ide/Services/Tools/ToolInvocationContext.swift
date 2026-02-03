import Foundation

struct ToolInvocationContext {
    let mode: String
    let toolCallId: String
    let patchSetId: String

    static func from(arguments: [String: Any]) -> ToolInvocationContext {
        let mode = (arguments["mode"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "apply"
        let toolCallId = (arguments["_tool_call_id"] as? String) ?? UUID().uuidString
        let patchSetId = (arguments["patch_set_id"] as? String)
            ?? (arguments["_conversation_id"] as? String)
            ?? "default"

        return ToolInvocationContext(mode: mode, toolCallId: toolCallId, patchSetId: patchSetId)
    }
}
