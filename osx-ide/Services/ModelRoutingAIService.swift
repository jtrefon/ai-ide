import Foundation

actor ModelRoutingAIService: AIService {
    private let openRouterService: AIService
    private let localService: AIService
    private let selectionStore: LocalModelSelectionStore

    init(
        openRouterService: AIService,
        localService: AIService,
        selectionStore: LocalModelSelectionStore = LocalModelSelectionStore()
    ) {
        self.openRouterService = openRouterService
        self.localService = localService
        self.selectionStore = selectionStore
    }

    func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
        if selectionStore.isOfflineModeEnabled() {
            return try await localService.sendMessage(request)
        }
        if shouldUseLocalModel(tools: request.tools) {
            return try await localService.sendMessage(request)
        }
        return try await openRouterService.sendMessage(request)
    }

    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
        if selectionStore.isOfflineModeEnabled() {
            return try await localService.sendMessage(request)
        }
        if shouldUseLocalModel(tools: request.tools) {
            return try await localService.sendMessage(request)
        }
        return try await openRouterService.sendMessage(request)
    }

    func explainCode(_ code: String) async throws -> String {
        if selectionStore.isOfflineModeEnabled() {
            return try await localService.explainCode(code)
        }
        if shouldUseLocalModel(tools: nil) {
            return try await localService.explainCode(code)
        }
        return try await openRouterService.explainCode(code)
    }

    func refactorCode(_ code: String, instructions: String) async throws -> String {
        if selectionStore.isOfflineModeEnabled() {
            return try await localService.refactorCode(code, instructions: instructions)
        }
        if shouldUseLocalModel(tools: nil) {
            return try await localService.refactorCode(code, instructions: instructions)
        }
        return try await openRouterService.refactorCode(code, instructions: instructions)
    }

    func generateCode(_ prompt: String) async throws -> String {
        if selectionStore.isOfflineModeEnabled() {
            return try await localService.generateCode(prompt)
        }
        if shouldUseLocalModel(tools: nil) {
            return try await localService.generateCode(prompt)
        }
        return try await openRouterService.generateCode(prompt)
    }

    func fixCode(_ code: String, error: String) async throws -> String {
        if selectionStore.isOfflineModeEnabled() {
            return try await localService.fixCode(code, error: error)
        }
        if shouldUseLocalModel(tools: nil) {
            return try await localService.fixCode(code, error: error)
        }
        return try await openRouterService.fixCode(code, error: error)
    }

    private func shouldUseLocalModel(tools: [AITool]?) -> Bool {
        let selected = selectionStore.selectedModelId()
        guard !selected.isEmpty else { return false }
        guard let model = LocalModelCatalog.model(id: selected) else { return false }
        guard LocalModelFileStore.isModelInstalled(model) else { return false }
        return tools?.isEmpty != false
    }
}
