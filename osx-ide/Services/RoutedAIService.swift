import Foundation

actor RoutedAIService: AIServiceStreaming {
    private let remote: AIService
    private let local: AIService
    private let providerStore: AIProviderSettingsStore
    private let localSettingsStore: LocalModelSettingsStore

    init(
        remote: AIService,
        local: AIService,
        providerStore: AIProviderSettingsStore = AIProviderSettingsStore(),
        localSettingsStore: LocalModelSettingsStore = LocalModelSettingsStore()
    ) {
        self.remote = remote
        self.local = local
        self.providerStore = providerStore
        self.localSettingsStore = localSettingsStore
    }

    func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
        try await activeService().sendMessage(request)
    }

    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
        try await activeService().sendMessage(request)
    }

    func sendMessageStream(
        _ request: AIServiceHistoryRequest,
        onChunk: @MainActor @Sendable @escaping (String) -> Void
    ) async throws -> AIServiceResponse {
        let service = activeService()
        if let streaming = service as? any AIServiceStreaming {
            return try await streaming.sendMessageStream(request, onChunk: onChunk)
        }
        return try await service.sendMessage(request)
    }

    func explainCode(_ code: String) async throws -> String {
        try await activeService().explainCode(code)
    }

    func refactorCode(_ code: String, instructions: String) async throws -> String {
        try await activeService().refactorCode(code, instructions: instructions)
    }

    func generateCode(_ prompt: String) async throws -> String {
        try await activeService().generateCode(prompt)
    }

    func fixCode(_ code: String, error: String) async throws -> String {
        try await activeService().fixCode(code, error: error)
    }

    private func activeService() -> AIService {
        let provider = providerStore.load()
        if provider == .local {
            let localSettings = localSettingsStore.load()
            if localSettings.isEnabled {
                return local
            }
            if localSettings.allowRemoteFallback {
                return remote
            }
            return local
        }
        return remote
    }
}
