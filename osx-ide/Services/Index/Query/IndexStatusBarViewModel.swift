import Foundation
import Combine

@MainActor
final class IndexStatusBarViewModel: ObservableObject {
    @Published private(set) var isIndexing: Bool = false
    @Published private(set) var processedCount: Int = 0
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var currentFile: URL? = nil
    @Published private(set) var stats: IndexStats? = nil

    @Published private(set) var isAIEnriching: Bool = false
    @Published private(set) var aiProcessedCount: Int = 0
    @Published private(set) var aiTotalCount: Int = 0
    @Published private(set) var aiCurrentFile: URL? = nil

    private let codebaseIndexProvider: () -> CodebaseIndexProtocol?
    private let eventBus: EventBusProtocol
    private var cancellables = Set<AnyCancellable>()
    private var statsTimer: AnyCancellable?

    init(codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?, eventBus: EventBusProtocol) {
        self.codebaseIndexProvider = codebaseIndexProvider
        self.eventBus = eventBus

        subscribeToEvents()
        startStatsPolling()
        refreshStats()
    }

    var statusText: String {
        if isAIEnriching {
            if aiTotalCount > 0 {
                let fileName = aiCurrentFile?.lastPathComponent
                if let fileName, !fileName.isEmpty {
                    return "AI Enriching \(aiProcessedCount)/\(aiTotalCount): \(fileName)"
                }
                return "AI Enriching \(aiProcessedCount)/\(aiTotalCount)"
            }
            return "AI Enriching…"
        }

        if isIndexing {
            if totalCount > 0 {
                let fileName = currentFile?.lastPathComponent
                if let fileName, !fileName.isEmpty {
                    return "Indexing \(processedCount)/\(totalCount): \(fileName)"
                }
                return "Indexing \(processedCount)/\(totalCount)"
            }
            return "Indexing…"
        }

        if let stats {
            if stats.totalProjectFileCount > 0 {
                let indexed = min(stats.indexedResourceCount, stats.totalProjectFileCount)
                let aiDenom = max(0, stats.aiEnrichableProjectFileCount)
                let ai = min(stats.aiEnrichedResourceCount, aiDenom)
                return "Index \(indexed)/\(stats.totalProjectFileCount) | AI \(ai)/\(aiDenom)"
            }
            return "Index: \(stats.indexedResourceCount) files"
        }

        return "Index: unavailable"
    }

    var metricsText: String {
        guard let stats else {
            return ""
        }

        let size = formatBytes(stats.databaseSizeBytes)
        let score = stats.aiEnrichedResourceCount > 0 && stats.averageAIQualityScore > 0 ? stats.averageAIQualityScore : stats.averageQualityScore
        let quality = score > 0 ? String(format: "%.0f", score) : "0"
        return "C \(stats.classCount) | F \(stats.functionCount) | S \(stats.symbolCount) | Q \(quality) | M \(stats.memoryCount) (LT \(stats.longTermMemoryCount)) | DB \(size)"
    }

    private func subscribeToEvents() {
        eventBus.subscribe(to: IndexingStartedEvent.self) { [weak self] _ in
            guard let self else { return }
            self.isIndexing = true
            self.processedCount = 0
            self.totalCount = max(self.totalCount, 0)
            self.currentFile = nil
        }
        .store(in: &cancellables)

        eventBus.subscribe(to: IndexingProgressEvent.self) { [weak self] event in
            guard let self else { return }
            self.isIndexing = true
            self.processedCount = event.processedCount
            self.totalCount = event.totalCount
            self.currentFile = event.currentFile
        }
        .store(in: &cancellables)

        eventBus.subscribe(to: IndexingCompletedEvent.self) { [weak self] _ in
            guard let self else { return }
            self.isIndexing = false
            self.currentFile = nil
            self.refreshStats()
        }
        .store(in: &cancellables)

        eventBus.subscribe(to: AIEnrichmentStartedEvent.self) { [weak self] _ in
            guard let self else { return }
            self.isAIEnriching = true
            self.aiProcessedCount = 0
            self.aiTotalCount = max(self.aiTotalCount, 0)
            self.aiCurrentFile = nil
        }
        .store(in: &cancellables)

        eventBus.subscribe(to: AIEnrichmentProgressEvent.self) { [weak self] event in
            guard let self else { return }
            self.isAIEnriching = true
            self.aiProcessedCount = event.processedCount
            self.aiTotalCount = event.totalCount
            self.aiCurrentFile = event.currentFile
        }
        .store(in: &cancellables)

        eventBus.subscribe(to: AIEnrichmentCompletedEvent.self) { [weak self] _ in
            guard let self else { return }
            self.isAIEnriching = false
            self.aiCurrentFile = nil
            self.refreshStats()
        }
        .store(in: &cancellables)
    }

    private func startStatsPolling() {
        statsTimer = Timer
            .publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshStats()
            }
    }

    private func refreshStats() {
        guard let codebaseIndex = codebaseIndexProvider() else { return }
        Task { @MainActor in
            self.stats = try? await codebaseIndex.getStats()
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let absBytes = Double(bytes)
        if absBytes < 1024 { return "\(bytes) B" }
        let kb = absBytes / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.2f GB", gb)
    }
}
