import Foundation
import Combine

extension CodebaseIndex {
    public convenience init(eventBus: EventBusProtocol) throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        try self.init(eventBus: eventBus, projectRoot: root, aiService: OpenRouterAIService(eventBus: eventBus))
    }

    public func start() {
        print("CodebaseIndex service started")
    }

    public func stop() {
        isEnabled = false
        aiEnrichmentAfterIndexCancellable?.cancel()
        aiEnrichmentAfterIndexCancellable = nil
        aiEnrichmentTask?.cancel()
        aiEnrichmentTask = nil
        coordinator.stop()
        Task { await database.shutdown() }
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        coordinator.setEnabled(enabled)
    }

    public func reindexProject() {
        reindexProject(aiEnrichmentEnabled: false)
    }

    public func reindexProject(aiEnrichmentEnabled: Bool) {
        guard isEnabled else { return }
        coordinator.reindexProject(rootURL: projectRoot)

        if aiEnrichmentEnabled {
            aiEnrichmentAfterIndexCancellable?.cancel()
            aiEnrichmentAfterIndexCancellable = eventBus.subscribe(
                to: ProjectReindexCompletedEvent.self
            ) { [weak self] _ in
                guard let self else { return }
                self.aiEnrichmentAfterIndexCancellable?.cancel()
                self.aiEnrichmentAfterIndexCancellable = nil
                self.runAIEnrichment()
            }
        }
    }
}
