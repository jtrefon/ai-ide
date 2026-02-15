import Foundation
import Combine

@MainActor
public class IndexCoordinator {
    private let eventBus: EventBusProtocol
    private let indexer: IndexerActor
    private var cancellables = Set<AnyCancellable>()
    private let debounceSubject = PassthroughSubject<URL, Never>()
    private let config: IndexConfiguration
    private var isEnabled: Bool
    private var reindexTask: Task<Void, Never>?
    private var singleFileTasks: [UUID: Task<Void, Never>] = [:]
    private var generation: UInt64 = 0
    private let projectRoot: URL?

    public init(
        eventBus: EventBusProtocol,
        indexer: IndexerActor,
        config: IndexConfiguration = .default,
        projectRoot: URL? = nil
    ) {
        self.eventBus = eventBus
        self.indexer = indexer
        self.config = config
        self.isEnabled = config.enabled
        self.projectRoot = projectRoot?.standardizedFileURL

        if let projectRoot = projectRoot {
            Task {
                await IndexLogger.shared.setup(projectRoot: projectRoot)
                await IndexLogger.shared.log("IndexCoordinator initialized with root: \(projectRoot.path)")
            }
        }

        setupSubscriptions()
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    public func stop() {
        generation &+= 1
        isEnabled = false

        reindexTask?.cancel()
        reindexTask = nil

        for (_, task) in singleFileTasks {
            task.cancel()
        }
        singleFileTasks.removeAll()

        cancellables.removeAll()
    }

    public func reindexProject(rootURL: URL) {
        guard isEnabled else {
            Task { @MainActor in await IndexLogger.shared.log("Reindex skipped: Indexing is disabled") }
            return
        }

        generation &+= 1
        let localGeneration = generation
        reindexTask?.cancel()
        reindexTask = Task { @MainActor in
            await performReindex(rootURL: rootURL, localGeneration: localGeneration)
        }
    }

    private func performReindex(rootURL: URL, localGeneration: UInt64) async {
        let start = Date()
        await IndexLogger.shared.log("Starting project reindex for: \(rootURL.path)")
        await eventBus.publish(IndexingStartedEvent())

        let files = IndexFileEnumerator.enumerateProjectFiles(
            rootURL: rootURL,
            excludePatterns: config.excludePatterns
        )
        let total = files.count
        await IndexLogger.shared.log("Found \(total) files to index")

        let processed = await processIndexFiles(files, total: total, localGeneration: localGeneration)

        if Task.isCancelled || localGeneration != generation { return }

        let duration = Date().timeIntervalSince(start)
        await IndexLogger.shared.log(
            "Reindex completed: \(processed)/\(total) files in " +
                "\(String(format: "%.2f", duration))s"
        )
        await eventBus.publish(IndexingCompletedEvent(indexedCount: processed, duration: duration))
        await eventBus.publish(ProjectReindexCompletedEvent(indexedCount: processed, duration: duration))
    }

    private func processIndexFiles(_ files: [URL], total: Int, localGeneration: UInt64) async -> Int {
        var processed = 0
        for file in files {
            if Task.isCancelled || localGeneration != generation { break }
            if !isEnabled {
                await IndexLogger.shared.log("Reindex aborted: Indexing was disabled during process")
                break
            }
            await publishProgress(processed: processed, total: total, file: file)
            do {
                try await indexer.indexFile(at: file)
                processed += 1
            } catch {
                await IndexLogger.shared.log("Failed to index file \(file.path): \(error)")
            }
            await publishProgress(processed: processed, total: total, file: file)
        }
        return processed
    }

    private func publishProgress(processed: Int, total: Int, file: URL) async {
        await eventBus.publish(
            IndexingProgressEvent(
                processedCount: processed,
                totalCount: total,
                currentFile: file
            )
        )
    }

    private func setupSubscriptions() {
        setupFileEventSubscriptions()
        setupDebounceSubscription()
    }

    private func setupFileEventSubscriptions() {
        setupFileCreatedSubscription()
        setupFileModifiedSubscription()
        setupFileRenamedSubscription()
        setupFileDeletedSubscription()
    }

    private func setupFileCreatedSubscription() {
        eventBus.subscribe(to: FileCreatedEvent.self) { [weak self] event in
            guard let self else { return }
            guard self.isEnabled else { return }
            guard self.isPathWithinProjectRoot(event.url) else { return }
            self.debounceSubject.send(event.url)
        }
        .store(in: &cancellables)
    }

    private func setupFileModifiedSubscription() {
        eventBus.subscribe(to: FileModifiedEvent.self) { [weak self] event in
            guard let self else { return }
            guard self.isEnabled else { return }
            guard self.isPathWithinProjectRoot(event.url) else { return }
            self.debounceSubject.send(event.url)
        }
        .store(in: &cancellables)
    }

    private func setupFileRenamedSubscription() {
        eventBus.subscribe(to: FileRenamedEvent.self) { [weak self] event in
            guard let self else { return }
            guard self.isEnabled else { return }
            guard self.isPathWithinProjectRoot(event.oldUrl), self.isPathWithinProjectRoot(event.newUrl) else { return }
            Task {
                try? await self.indexer.removeFile(at: event.oldUrl)
                self.debounceSubject.send(event.newUrl)
            }
        }
        .store(in: &cancellables)
    }

    private func setupFileDeletedSubscription() {
        eventBus.subscribe(to: FileDeletedEvent.self) { [weak self] event in
            guard let self else { return }
            guard self.isEnabled else { return }
            guard self.isPathWithinProjectRoot(event.url) else { return }
            Task {
                try? await self.indexer.removeFile(at: event.url)
            }
        }
        .store(in: &cancellables)
    }

    private func setupDebounceSubscription() {
        debounceSubject
            .debounce(for: .milliseconds(config.debounceMs), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] url in
                self?.indexFile(url)
            }
            .store(in: &cancellables)
    }

    private func indexFile(_ url: URL) {
        guard isPathWithinProjectRoot(url) else { return }
        let localGeneration = generation

        let id = UUID()
        let task = Task { @MainActor in
            do {
                guard isEnabled else {
                    await IndexLogger.shared.log("Single file index skipped for \(url.path): Indexing disabled")
                    return
                }
                await IndexLogger.shared.log("Indexing single file: \(url.path)")
                await eventBus.publish(IndexingStartedEvent())
                await eventBus.publish(IndexingProgressEvent(processedCount: 0, totalCount: 1, currentFile: url))
                if Task.isCancelled || localGeneration != generation { return }
                try await indexer.indexFile(at: url)
                if Task.isCancelled || localGeneration != generation { return }
                await eventBus.publish(IndexingProgressEvent(processedCount: 1, totalCount: 1, currentFile: url))
                await eventBus.publish(IndexingCompletedEvent(indexedCount: 1, duration: 0))
                await IndexLogger.shared.log("Successfully indexed single file: \(url.path)")
            } catch {
                await IndexLogger.shared.log("Failed to index file \(url.path): \(error)")
            }

            self.singleFileTasks[id] = nil
        }

        singleFileTasks[id] = task
    }

    private func isPathWithinProjectRoot(_ url: URL) -> Bool {
        guard let projectRoot else { return true }
        let candidate = url.standardizedFileURL.path
        let rootPath = projectRoot.path
        return candidate == rootPath || candidate.hasPrefix(rootPath + "/")
    }
}
