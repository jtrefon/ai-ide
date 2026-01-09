import Foundation

struct PatchSetApplyTool: AITool {
    let name = "patchset_apply"
    let description = "Apply a staged patch set to disk."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "patch_set_id": [
                    "type": "string",
                    "description": "The patch set identifier under .ide/staging."
                ]
            ],
            "required": ["patch_set_id"]
        ]
    }

    let eventBus: EventBusProtocol
    let projectRoot: URL

    func execute(arguments: [String: Any]) async throws -> String {
        guard let id = arguments["patch_set_id"] as? String, !id.isEmpty else {
            throw AppError.aiServiceError("Missing 'patch_set_id' for patchset_apply")
        }

        guard let manifest = await PatchSetStore.shared.loadManifest(patchSetId: id) else {
            throw AppError.aiServiceError("Patch set not found: \(id)")
        }

        let uniquePaths = Array(Set(manifest.entries.map { $0.relativePath })).sorted()
        var existedBefore: [String: Bool] = [:]
        existedBefore.reserveCapacity(uniquePaths.count)
        for rel in uniquePaths {
            let url = projectRoot.appendingPathComponent(rel)
            existedBefore[rel] = FileManager.default.fileExists(atPath: url.path)
        }

        let checkpointId = try await CheckpointManager.shared.createCheckpoint(relativePaths: uniquePaths)

        let touched = try await PatchSetStore.shared.applyPatchSet(patchSetId: id)

        Task { @MainActor in
            for entry in manifest.entries {
                let rel = entry.relativePath
                let url = projectRoot.appendingPathComponent(rel)
                let existed = existedBefore[rel] ?? false
                let existsNow = FileManager.default.fileExists(atPath: url.path)

                switch entry.kind {
                case .delete:
                    if existed {
                        eventBus.publish(FileDeletedEvent(url: url))
                    }
                case .write, .create, .replace:
                    if existsNow {
                        if existed {
                            eventBus.publish(FileModifiedEvent(url: url))
                        } else {
                            eventBus.publish(FileCreatedEvent(url: url))
                        }
                    }
                }
            }
        }

        if touched.isEmpty {
            return "Applied patch set \(id). Created checkpoint \(checkpointId)."
        }
        return "Applied patch set \(id). Created checkpoint \(checkpointId). Touched files:\n" + touched.joined(separator: "\n")
    }
}
