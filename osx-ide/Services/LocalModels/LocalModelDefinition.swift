import Foundation
@preconcurrency import MLXLMCommon

struct LocalModelArtifact: Hashable, Sendable {
    let fileName: String
    let url: URL
}

struct FIMTokens: Sendable {
    let prefix: String
    let suffix: String
    let middle: String
    let endOfText: String

    static let qwen25Coder = FIMTokens(
        prefix: "<|fim_prefix|>",
        suffix: "<|fim_suffix|>",
        middle: "<|fim_middle|>",
        endOfText: "<|endoftext|>"
    )
}

struct LocalModelDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let artifacts: [LocalModelArtifact]
    let defaultContextLength: Int
    let toolCallFormat: ToolCallFormat?
    let supportsQuantizedKVCache: Bool
    let supportsFIM: Bool

    init(id: String, displayName: String, artifacts: [LocalModelArtifact], defaultContextLength: Int = 4096, toolCallFormat: ToolCallFormat? = nil, supportsQuantizedKVCache: Bool = true, supportsFIM: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.artifacts = artifacts
        self.defaultContextLength = defaultContextLength
        self.toolCallFormat = toolCallFormat
        self.supportsQuantizedKVCache = supportsQuantizedKVCache
        self.supportsFIM = supportsFIM
    }

    var fimTokens: FIMTokens? {
        guard supportsFIM else { return nil }
        return .qwen25Coder
    }
}
