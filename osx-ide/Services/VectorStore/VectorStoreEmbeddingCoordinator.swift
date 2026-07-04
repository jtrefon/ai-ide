import Foundation
import Combine

public actor VectorStoreEmbeddingCoordinator {
    private weak var vectorStoreService: VectorStoreService?
    private let projectRoot: URL
    private let eventBus: EventBusProtocol
    private let embedder: HashingMemoryEmbeddingGenerator
    private let logFileQueue = DispatchQueue(label: "com.vectorstore.embedding.log", qos: .utility)

    private var pendingConversations: Set<String> = []
    private var flushTask: Task<Void, Never>?
    private var embeddedTurnCounts: [String: Int] = [:]
    private var bag: Set<AnyCancellable> = []

    private static let debounceNanoseconds: UInt64 = 2_000_000_000
    private static let flushThreshold = 5

    public init(
        vectorStoreService: VectorStoreService,
        projectRoot: URL,
        eventBus: EventBusProtocol,
        dimensions: Int = 512
    ) {
        self.vectorStoreService = vectorStoreService
        self.projectRoot = projectRoot
        self.eventBus = eventBus
        self.embedder = HashingMemoryEmbeddingGenerator(dimensions: dimensions)
    }

    public func start() {
        let handler: @Sendable (URL) -> Void = { [weak self] url in
            Task { [weak self] in
                await self?.handleFileEvent(url: url)
            }
        }
        eventBus.subscribe(to: IDEFileCreatedEvent.self) { handler($0.url) }.store(in: &bag)
        eventBus.subscribe(to: IDEFileModifiedEvent.self) { handler($0.url) }.store(in: &bag)
    }

    private func handleFileEvent(url: URL) {
        guard url.lastPathComponent == "conversation.ndjson" else { return }
        let convId = url.deletingLastPathComponent().lastPathComponent
        pendingConversations.insert(convId)
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            await self?.flushIfNeeded()
        }
    }

    private func flushIfNeeded() async {
        guard !pendingConversations.isEmpty else { return }
        await flush()
    }

    private func hasReachedThreshold(_ convs: Set<String>) -> Bool {
        convs.count >= Self.flushThreshold
    }

    private func flush() async {
        let convs = pendingConversations
        pendingConversations = []
        flushTask = nil

        for convId in convs {
            let convDir = ConversationScopedNDJSONStore.projectConversationDirectory(
                projectRoot: projectRoot,
                conversationId: convId
            )
            let fileURL = convDir.appendingPathComponent("conversation.ndjson")
            guard let data = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let eventLines = data.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let totalTurns = eventLines.count / 2
            let alreadyEmbedded = embeddedTurnCounts[convId] ?? 0

            guard totalTurns > alreadyEmbedded else { continue }

            let queryStart = alreadyEmbedded * 2
            guard queryStart + 1 < eventLines.count else { continue }

            for i in stride(from: queryStart, to: eventLines.count - 1, by: 2) {
                let queryLine = eventLines[i]
                let responseLine = eventLines[i + 1]
                guard let queryEvent = try? JSONDecoder().decode(ConversationLogEvent.self, from: Data(queryLine.utf8)),
                      let responseEvent = try? JSONDecoder().decode(ConversationLogEvent.self, from: Data(responseLine.utf8)),
                      let queryText = extractString(from: queryEvent.data?["content"]),
                      let responseText = extractString(from: responseEvent.data?["content"]) else {
                    break
                }

                let qVec = (try? await embedder.generateEmbedding(for: queryText)) ?? []
                let rVec = (try? await embedder.generateEmbedding(for: responseText)) ?? []
                guard !qVec.isEmpty, !rVec.isEmpty else { break }

                let turn = VectorStoreService.ConversationTurn(
                    query: queryText,
                    response: String(responseText.prefix(500)),
                    source: "conversation",
                    category: convId
                )
                try? await vectorStoreService?.storeConversationTurn(
                    turn: turn,
                    queryVector: qVec,
                    responseVector: rVec
                )
                embeddedTurnCounts[convId] = (embeddedTurnCounts[convId] ?? 0) + 1
            }
        }
    }

    public func setEmbeddedTurnCount(conversationId: String, count: Int) {
        embeddedTurnCounts[conversationId] = count
    }

    private func extractString(from logValue: LogValue?) -> String? {
        guard case .string(let value) = logValue else { return nil }
        return value
    }
}
