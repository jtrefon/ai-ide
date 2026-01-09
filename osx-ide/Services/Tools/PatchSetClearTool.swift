import Foundation

struct PatchSetClearTool: AITool {
    let name = "patchset_clear"
    let description = "Delete a staged patch set from .ide/staging."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "patch_set_id": [
                    "type": "string",
                    "description": "The patch set identifier to delete."
                ]
            ],
            "required": ["patch_set_id"]
        ]
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let id = arguments["patch_set_id"] as? String, !id.isEmpty else {
            throw AppError.aiServiceError("Missing 'patch_set_id' for patchset_clear")
        }
        try await PatchSetStore.shared.clearPatchSet(patchSetId: id)
        return "Deleted patch set \(id)."
    }
}
