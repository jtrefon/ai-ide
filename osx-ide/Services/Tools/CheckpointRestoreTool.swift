import Foundation

struct CheckpointRestoreTool: AITool {
    let name = "checkpoint_restore"
    let description = "Restore a checkpoint to disk."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "checkpoint_id": [
                    "type": "string",
                    "description": "Checkpoint identifier under .ide/checkpoints."
                ]
            ],
            "required": ["checkpoint_id"]
        ]
    }

    let eventBus: EventBusProtocol
    let projectRoot: URL

    func execute(arguments: [String: Any]) async throws -> String {
        guard let id = arguments["checkpoint_id"] as? String, !id.isEmpty else {
            throw AppError.aiServiceError("Missing 'checkpoint_id' for checkpoint_restore")
        }

        let manifest = await CheckpointManager.shared.loadManifest(checkpointId: id)
        let entries = manifest?.entries ?? []

        var existedBefore: [String: Bool] = [:]
        existedBefore.reserveCapacity(entries.count)
        for entry in entries {
            let url = projectRoot.appendingPathComponent(entry.relativePath)
            existedBefore[entry.relativePath] = FileManager.default.fileExists(atPath: url.path)
        }

        let restored = try await CheckpointManager.shared.restoreCheckpoint(checkpointId: id)

        Task { @MainActor in
            for rel in restored {
                let url = projectRoot.appendingPathComponent(rel)
                let existsNow = FileManager.default.fileExists(atPath: url.path)
                let existed = existedBefore[rel] ?? false

                if existsNow {
                    if existed {
                        eventBus.publish(FileModifiedEvent(url: url))
                    } else {
                        eventBus.publish(FileCreatedEvent(url: url))
                    }
                } else {
                    if existed {
                        eventBus.publish(FileDeletedEvent(url: url))
                    }
                }
            }
        }

        if restored.isEmpty { return "Restored checkpoint \(id)." }
        return "Restored checkpoint \(id). Touched files:\n" + restored.joined(separator: "\n")
    }
}
