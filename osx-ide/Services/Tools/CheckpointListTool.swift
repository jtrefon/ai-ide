import Foundation

struct CheckpointListTool: AITool {
    let name = "checkpoint_list"
    let description = "List checkpoints under .ide/checkpoints."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [:]
        ]
    }

    func execute(arguments _: ToolArguments) async throws -> String {
        let ids = await CheckpointManager.shared.listCheckpointIds()
        if ids.isEmpty { return "No checkpoints." }
        return ids.joined(separator: "\n")
    }
}
