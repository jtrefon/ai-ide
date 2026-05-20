//
//  AIServicesFactory.swift
//  osx-ide
//
//  Extracted from DependencyContainer — Phase A decomposition.
//

import Foundation

// MARK: - AIServiceBundle

struct AIServiceBundle {
    let openRouterService: OpenRouterAIService
    let alibabaService: OpenRouterAIService
    let kiloCodeService: OpenRouterAIService
    let deepSeekService: OpenRouterAIService
    let localModelService: LocalModelProcessAIService
    let selectionStore: LocalModelSelectionStore
    let providerSelectionStore: AIProviderSelectionStore
    let router: ModelRoutingAIService
}

// MARK: - Factory

enum AIServicesFactory {

    static func makeAIServices(
        launchContext: AppLaunchContext,
        settingsStore: SettingsStore,
        eventBus: any EventBusProtocol,
        activityCoordinator: any AgentActivityCoordinating
    ) -> AIServiceBundle {
        let openRouterService = OpenRouterAIService(
            settingsStore: OpenRouterSettingsStore(settingsStore: settingsStore),
            eventBus: eventBus,
            providerName: "OpenRouter",
            testConfigurationProvider: TestConfigurationProvider.shared
        )
        let alibabaService = OpenRouterAIService(
            settingsStore: AlibabaSettingsStore(settingsStore: settingsStore),
            eventBus: eventBus,
            providerName: "Alibaba Cloud",
            supportsStreamingWithTools: false,
            testConfigurationProvider: TestConfigurationProvider.shared
        )
        let kiloCodeService = OpenRouterAIService(
            settingsStore: KiloCodeSettingsStore(settingsStore: settingsStore),
            eventBus: eventBus,
            providerName: "Kilo Code",
            supportsStreamingWithTools: true,
            supportsNativeReasoning: true,
            testConfigurationProvider: TestConfigurationProvider.shared
        )
        let deepSeekService = OpenRouterAIService(
            settingsStore: DeepSeekSettingsStore(settingsStore: settingsStore),
            eventBus: eventBus,
            providerName: "DeepSeek",
            supportsStreamingWithTools: true,
            // DeepSeek thinking mode is model-dependent (deepseek-reasoner vs deepseek-chat),
            // not controlled by a reasoning parameter. The API ignores or errors on it.
            supportsNativeReasoning: false,
            testConfigurationProvider: TestConfigurationProvider.shared
        )
        let selectionStore = LocalModelSelectionStore(settingsStore: settingsStore)
        let providerSelectionStore = AIProviderSelectionStore(settingsStore: settingsStore)
        let localModelEventBus: (any EventBusProtocol)? = launchContext.isTesting ? nil : eventBus
        let localModelService = LocalModelProcessAIService(
            selectionStore: selectionStore,
            eventBus: localModelEventBus,
            activityCoordinator: activityCoordinator,
            launchContext: launchContext
        )
        let router = ModelRoutingAIService(
            openRouterService: openRouterService,
            alibabaService: alibabaService,
            kiloCodeService: kiloCodeService,
            deepSeekService: deepSeekService,
            localService: localModelService,
            selectionStore: selectionStore,
            providerSelectionStore: providerSelectionStore
        )
        return AIServiceBundle(
            openRouterService: openRouterService,
            alibabaService: alibabaService,
            kiloCodeService: kiloCodeService,
            deepSeekService: deepSeekService,
            localModelService: localModelService,
            selectionStore: selectionStore,
            providerSelectionStore: providerSelectionStore,
            router: router
        )
    }

    @MainActor
    static func makeInlineCompletionEngine(
        aiServices: AIServiceBundle,
        projectRootProvider: @escaping () -> URL?,
        codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?
    ) -> InlineCompletionEngine {
        return InlineCompletionEngine(
            settingsStore: InlineCompletionSettingsStore(),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: CompletionRetrievalLayer(
                projectRootProvider: projectRootProvider,
                codebaseIndexProvider: codebaseIndexProvider
            ),
            inferenceService: CompletionInferenceService(
                provider: AIServiceInlineCompletionProvider(
                    remoteServiceProvider: {
                        switch await aiServices.providerSelectionStore.selectedRemoteProvider() {
                        case .openRouter:
                            return aiServices.openRouterService
                        case .alibabaCloud:
                            return aiServices.alibabaService
                        case .kiloCode:
                            return aiServices.kiloCodeService
                        case .deepSeek:
                            return aiServices.deepSeekService
                        }
                    },
                    localServiceProvider: { aiServices.localModelService },
                    localModelSelectionStore: aiServices.selectionStore
                )
            ),
            ranker: SuggestionRanker()
        )
    }
}
