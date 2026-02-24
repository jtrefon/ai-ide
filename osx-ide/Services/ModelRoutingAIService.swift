//
//  ModelRoutingAIService.swift
//  osx-ide
//
//  Routes between OpenRouter and local MLX models based on settings and model capability
//

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
        // Check if offline mode is enabled
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        
        // Simple routing: if offline mode, use MLX; otherwise use OpenRouter
        if isOfflineMode {
            // Get MLX capability
            let capability = MLXCapability()
            
            // MLX doesn't support Agent mode - force Chat mode
            if request.mode == .agent {
                let adjustedRequest = adjustRequestForMLX(request, capability: capability)
                return try await localService.sendMessage(adjustedRequest)
            }
            return try await localService.sendMessage(request)
        }
        
        // Online mode: always use OpenRouter (not MLX)
        return try await openRouterService.sendMessage(request)
    }

    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
        // Check if offline mode is enabled
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        
        // Simple routing: if offline mode, use MLX; otherwise use OpenRouter
        if isOfflineMode {
            // Get MLX capability
            let capability = MLXCapability()
            
            // MLX doesn't support Agent mode - force Chat mode
            if request.mode == .agent {
                let adjustedRequest = adjustRequestForMLX(request, capability: capability)
                return try await localService.sendMessage(adjustedRequest)
            }
            return try await localService.sendMessage(request)
        }
        
        // Online mode: always use OpenRouter (not MLX)
        return try await openRouterService.sendMessage(request)
    }

    /// Streaming version - routes to appropriate service based on offline mode
    func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
        // Check if offline mode is enabled
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()

        // Simple routing: if offline mode, use MLX; otherwise use OpenRouter
        if isOfflineMode {
            // Get MLX capability
            let capability = MLXCapability()

            // MLX doesn't support Agent mode - force Chat mode
            if request.mode == .agent {
                let adjustedRequest = adjustRequestForMLX(request, capability: capability)
                return try await localService.sendMessageStreaming(adjustedRequest, runId: runId)
            }
            return try await localService.sendMessageStreaming(request, runId: runId)
        }
        
        // Online mode: always use OpenRouter (not MLX)
        return try await openRouterService.sendMessageStreaming(request, runId: runId)
    }

    func explainCode(_ code: String) async throws -> String {
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        if isOfflineMode {
            return try await localService.explainCode(code)
        }
        return try await openRouterService.explainCode(code)
    }

    func refactorCode(_ code: String, instructions: String) async throws -> String {
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        if isOfflineMode {
            return try await localService.refactorCode(code, instructions: instructions)
        }
        return try await openRouterService.refactorCode(code, instructions: instructions)
    }

    func generateCode(_ prompt: String) async throws -> String {
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        if isOfflineMode {
            return try await localService.generateCode(prompt)
        }
        return try await openRouterService.generateCode(prompt)
    }

    func fixCode(_ code: String, error: String) async throws -> String {
        let isOfflineMode = await selectionStore.isOfflineModeEnabled()
        if isOfflineMode {
            return try await localService.fixCode(code, error: error)
        }
        return try await openRouterService.fixCode(code, error: error)
    }

    // MARK: - Capability Detection

    /// Returns the appropriate model capability based on configuration
    private func getCapability(isOfflineMode: Bool, willUseLocal: Bool) -> any ModelCapability {
        if isOfflineMode || willUseLocal {
            return MLXCapability()
        }
        return OpenRouterCapability()
    }

    // MARK: - Request Adjustment for MLX

    /// Adjusts a request for MLX by forcing Chat mode and limiting tools
    /// NOTE: This logs a warning so users know why Agent mode was downgraded
    private func adjustRequestForMLX(
        _ request: AIServiceMessageWithProjectRootRequest,
        capability: any ModelCapability
    ) -> AIServiceMessageWithProjectRootRequest {
        // Log the downgrade for debugging
        let logger = AppLogger.shared
        Task {
            await logger.warning(
                category: .ai,
                message: "Agent mode requested but local model does not support advanced orchestration. " +
                "Falling back to Chat mode. Requested: \(request.mode), Using: Chat. " +
                "Use OpenRouter for Agent mode."
            )
        }
        
        // Filter tools to only RAG/index tools (read-only)
        let limitedTools = filterToolsForMLX(request.tools)
        
        return AIServiceMessageWithProjectRootRequest(
            message: request.message,
            context: request.context,
            tools: limitedTools,
            mode: .chat,  // Force Chat mode for MLX
            projectRoot: request.projectRoot
        )
    }

    /// Adjusts a history request for MLX by forcing Chat mode and limiting tools
    private func adjustRequestForMLX(
        _ request: AIServiceHistoryRequest,
        capability: any ModelCapability
    ) -> AIServiceHistoryRequest {
        // Log the downgrade for debugging
        let logger = AppLogger.shared
        Task {
            await logger.warning(
                category: .ai,
                message: "Agent mode requested but local model does not support advanced orchestration. " +
                "Falling back to Chat mode. Requested: \(request.mode), Using: Chat. " +
                "Use OpenRouter for Agent mode."
            )
        }
        
        // Filter tools to only RAG/index tools (read-only)
        let limitedTools = filterToolsForMLX(request.tools)
        
        return AIServiceHistoryRequest(
            messages: request.messages,
            context: request.context,
            tools: limitedTools,
            mode: .chat,  // Force Chat mode for MLX
            projectRoot: request.projectRoot,
            runId: request.runId,
            stage: request.stage,
            conversationId: request.conversationId
        )
    }

    /// Filters tools to only those suitable for MLX (RAG/index read-only tools)
    private func filterToolsForMLX(_ tools: [AITool]?) -> [AITool]? {
        guard let tools = tools else { return nil }

        // Reuse mode-based policy to avoid duplicating hardcoded tool lists.
        return AIMode.chat.allowedTools(from: tools)
    }

    // MARK: - Local Model Detection

    private func shouldUseLocalModel(tools: [AITool]?) async -> Bool {
        let selected = await selectionStore.selectedModelId()
        guard !selected.isEmpty else { return false }
        guard let model = LocalModelCatalog.model(id: selected) else { return false }
        guard LocalModelFileStore.isModelInstalled(model) else { return false }
        return tools?.isEmpty != false
    }
}
