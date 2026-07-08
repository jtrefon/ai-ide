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
    let openCodeGoService: OpenRouterAIService
    let openCodeGoSubscriptionService: OpenRouterAIService
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
            supportsNativeReasoning: false,
            testConfigurationProvider: TestConfigurationProvider.shared
        )
        let openCodeGoService = OpenRouterAIService(
            settingsStore: OpenCodeGoSettingsStore(settingsStore: settingsStore),
            eventBus: eventBus,
            providerName: "OpenCode Go",
            supportsStreamingWithTools: true,
            supportsNativeReasoning: true,
            testConfigurationProvider: TestConfigurationProvider.shared
        )
        let openCodeGoSubscriptionService = OpenRouterAIService(
            settingsStore: OpenCodeGoSubscriptionSettingsStore(settingsStore: settingsStore),
            eventBus: eventBus,
            providerName: "OpenCode Go (Subscription)",
            supportsStreamingWithTools: true,
            supportsNativeReasoning: true,
            testConfigurationProvider: TestConfigurationProvider.shared
        )
        let selectionStore = LocalModelSelectionStore(settingsStore: settingsStore)
        let providerSelectionStore = AIProviderSelectionStore(settingsStore: settingsStore)
        let localModelEventBus: (any EventBusProtocol)? = launchContext.isTesting ? nil : eventBus
        let testGenerator: LocalModelProcessAIService.LocalModelGenerating? = launchContext.isTesting
            ? LocalModelProcessAIService.NativeMLXGenerator.sharedTestGenerator
            : nil
        let localModelService = LocalModelProcessAIService(
            selectionStore: selectionStore,
            generator: testGenerator,
            eventBus: localModelEventBus,
            activityCoordinator: activityCoordinator,
            launchContext: launchContext
        )
        let registry = AIServiceRegistry(
            providerSelectionStore: providerSelectionStore,
            localSelectionStore: selectionStore
        )
        registry.register(provider: .openRouter, service: openRouterService)
        registry.register(provider: .alibabaCloud, service: alibabaService)
        registry.register(provider: .kiloCode, service: kiloCodeService)
        registry.register(provider: .deepSeek, service: deepSeekService)
        registry.register(provider: .openCodeGo, service: openCodeGoService)
        registry.register(provider: .openCodeGoSubscription, service: openCodeGoSubscriptionService)
        registry.register(provider: .local, service: localModelService)
        let router = ModelRoutingAIService(registry: registry)
        return AIServiceBundle(
            openRouterService: openRouterService,
            alibabaService: alibabaService,
            kiloCodeService: kiloCodeService,
            deepSeekService: deepSeekService,
            openCodeGoService: openCodeGoService,
            openCodeGoSubscriptionService: openCodeGoSubscriptionService,
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
                        case .openCodeGo:
                            return aiServices.openCodeGoService
                        case .openCodeGoSubscription:
                            return aiServices.openCodeGoSubscriptionService
                        }
                    },
                    localServiceProvider: { aiServices.localModelService },
                    localModelSelectionStore: aiServices.selectionStore
                )
            ),
            ranker: SuggestionRanker()
        )
    }

    @MainActor
    static func makeSnippetCompletionService(
        aiServices: AIServiceBundle,
        projectRootProvider: @escaping () -> URL?,
        codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?
    ) -> SnippetCompletionService {
        return SnippetCompletionService(
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
                        case .openCodeGo:
                            return aiServices.openCodeGoService
                        case .openCodeGoSubscription:
                            return aiServices.openCodeGoSubscriptionService
                        }
                    },
                    localServiceProvider: { aiServices.localModelService },
                    localModelSelectionStore: aiServices.selectionStore
                )
            ),
            retrievalLayer: CompletionRetrievalLayer(
                projectRootProvider: projectRootProvider,
                codebaseIndexProvider: codebaseIndexProvider
            ),
            ranker: SuggestionRanker()
        )
    }
}
