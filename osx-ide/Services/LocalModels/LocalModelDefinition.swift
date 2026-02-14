import Foundation
@preconcurrency import MLXLMCommon

struct LocalModelArtifact: Hashable, Sendable {
    let fileName: String
    let url: URL
}

struct LocalModelDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let artifacts: [LocalModelArtifact]
    let defaultContextLength: Int
    let toolCallFormat: ToolCallFormat?

    init(id: String, displayName: String, artifacts: [LocalModelArtifact], defaultContextLength: Int = 4096, toolCallFormat: ToolCallFormat? = nil) {
        self.id = id
        self.displayName = displayName
        self.artifacts = artifacts
        self.defaultContextLength = defaultContextLength
        self.toolCallFormat = toolCallFormat
    }
}
