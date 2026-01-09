import Foundation

struct PatchSetListTool: AITool {
    let name = "patchset_list"
    let description = "List staged patch sets under .ide/staging."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [:]
        ]
    }

    func execute(arguments _: [String: Any]) async throws -> String {
        let ids = await PatchSetStore.shared.listPatchSetIds()
        if ids.isEmpty { return "No staged patch sets." }
        return ids.joined(separator: "\n")
    }
}
