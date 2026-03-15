//
//  ModelRoutingAIService.swift
//  osx-ide
//
//  Routes between OpenRouter and local MLX models based on settings and model capability
//

import Foundation

actor ModelRoutingAIService: AIService, RemoteAIAccountStatusRefreshing {
    private let openRouterService: AIService
    private let alibabaService: AIService
    private let kiloCodeService: AIService
    private let localService: AIService
    private let selectionStore: LocalModelSelectionStore
    private let providerSelectionStore: AIProviderSelectionStore

    init(
        openRouterService: AIService,
        alibabaService: AIService,
        kiloCodeService: AIService,
        localService: AIService,
        selectionStore: LocalModelSelectionStore = LocalModelSelectionStore(),
        providerSelectionStore: AIProviderSelectionStore = AIProviderSelectionStore()
    ) {
        self.openRouterService = openRouterService
        self.alibabaService = alibabaService
        self.kiloCodeService = kiloCodeService
        self.localService = localService
        self.selectionStore = selectionStore
        self.providerSelectionStore = providerSelectionStore
    }

    private func selectedRemoteService() async -> AIService {
        switch await providerSelectionStore.selectedRemoteProvider() {
        case .openRouter:
            return openRouterService
        case .alibabaCloud:
            return alibabaService
        case .kiloCode:
            return kiloCodeService
        }
    }

    private func selectedService() async -> AIService {
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        return isOfflineMode ? localService : await selectedRemoteService()
    }

    private func localOrRemoteResponse(
        localOperation: (AIService) async throws -> AIServiceResponse,
        remoteOperation: (AIService) async throws -> AIServiceResponse
    ) async throws -> AIServiceResponse {
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        if isOfflineMode {
            return try await localOperation(localService)
        }
        return try await remoteOperation(await selectedRemoteService())
    }

    private func localOrRemoteString(
        localOperation: (AIService) async throws -> String,
        remoteOperation: (AIService) async throws -> String
    ) async throws -> String {
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        if isOfflineMode {
            return try await localOperation(localService)
        }
        return try await remoteOperation(await selectedRemoteService())
    }

    func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
        try await localOrRemoteResponse(
            localOperation: { try await $0.sendMessage(request) },
            remoteOperation: { try await $0.sendMessage(request) }
        )
    }

    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
        try await localOrRemoteResponse(
            localOperation: { try await $0.sendMessage(request) },
            remoteOperation: { try await $0.sendMessage(request) }
        )
    }

    /// Streaming version - routes to appropriate service based on offline mode
    func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        await AppLogger.shared.debug(
            category: .ai,
            message: "model_router.send_message_streaming",
            context: AppLogger.LogCallContext(metadata: [
                "offlineMode": isOfflineMode,
                "selectedRemoteProvider": await providerSelectionStore.selectedRemoteProvider().displayName,
                "stage": String(describing: request.stage),
                "runId": runId
            ])
        )

        if isOfflineMode {
            return try await localService.sendMessageStreaming(request, runId: runId)
        }
        return try await selectedRemoteService().sendMessageStreaming(request, runId: runId)
    }

    func explainCode(_ code: String) async throws -> String {
        try await localOrRemoteString(
            localOperation: { try await $0.explainCode(code) },
            remoteOperation: { try await $0.explainCode(code) }
        )
    }

    func refactorCode(_ code: String, instructions: String) async throws -> String {
        try await localOrRemoteString(
            localOperation: { try await $0.refactorCode(code, instructions: instructions) },
            remoteOperation: { try await $0.refactorCode(code, instructions: instructions) }
        )
    }

    func generateCode(_ prompt: String) async throws -> String {
        try await localOrRemoteString(
            localOperation: { try await $0.generateCode(prompt) },
            remoteOperation: { try await $0.generateCode(prompt) }
        )
    }

    func fixCode(_ code: String, error: String) async throws -> String {
        try await localOrRemoteString(
            localOperation: { try await $0.fixCode(code, error: error) },
            remoteOperation: { try await $0.fixCode(code, error: error) }
        )
    }

    func refreshAccountBalance(runId: String?) async {
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        guard !isOfflineMode else { return }
        let remoteService = await selectedRemoteService()
        await (remoteService as? RemoteAIAccountStatusRefreshing)?.refreshAccountBalance(runId: runId)
    }
}
