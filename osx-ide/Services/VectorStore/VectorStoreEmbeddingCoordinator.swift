import Foundation
import Combine

/// Subscribes to contextual data events and embeds content into the vector store.
/// Event-driven replacement for the FS-watching approach — content arrives
/// in-memory as typed structs, no file I/O, no debounce.
public actor VectorStoreEmbeddingCoordinator {
    private weak var vectorStoreService: VectorStoreService?
    private let eventBus: EventBusProtocol
    private let embedder: HashingMemoryEmbeddingGenerator
    private var bag: Set<AnyCancellable> = []

    /// Buffers the last user message per conversation for pairing with assistant responses.
    private var pendingQueries: [String: String] = [:]

    public init(
        vectorStoreService: VectorStoreService,
        eventBus: EventBusProtocol,
        dimensions: Int = 512
    ) {
        self.vectorStoreService = vectorStoreService
        self.eventBus = eventBus
        self.embedder = HashingMemoryEmbeddingGenerator(dimensions: dimensions)
    }

    public func start() {
        let ctxHandler: @Sendable (ContextLogEvent) -> Void = { [weak self] event in
            Task { [weak self] in await self?.handleContextLog(event) }
        }
        eventBus.subscribe(to: ContextLogEvent.self, handler: ctxHandler).store(in: &bag)

        let toolHandler: @Sendable (ToolResultEvent) -> Void = { [weak self] event in
            Task { [weak self] in await self?.handleToolResult(event) }
        }
        eventBus.subscribe(to: ToolResultEvent.self, handler: toolHandler).store(in: &bag)
    }

    // MARK: - ContextLogEvent

    private func handleContextLog(_ event: ContextLogEvent) async {
        guard let convId = event.conversationId else { return }

        if event.source == "chat.user_message" {
            pendingQueries[convId] = event.content
        } else if event.source == "chat.assistant_message" || event.source == "chat.response" {
            guard let queryText = pendingQueries.removeValue(forKey: convId) else { return }

            let qVec = (try? await embedder.generateEmbedding(for: queryText)) ?? []
            let rVec = (try? await embedder.generateEmbedding(for: event.content)) ?? []
            guard !qVec.isEmpty, !rVec.isEmpty else { return }

            try? await vectorStoreService?.addEntry(
                text: nil,
                vector: qVec,
                source: "conversation",
                category: convId,
                sourceReference: SourceReference(conversationId: convId, messageIndex: 0)
            )
            try? await vectorStoreService?.addEntry(
                text: nil,
                vector: rVec,
                source: "conversation",
                category: convId,
                sourceReference: SourceReference(conversationId: convId, messageIndex: 1)
            )
        }
    }

    // MARK: - ToolResultEvent

    private func handleToolResult(_ event: ToolResultEvent) async {
        guard event.type == "execute_success" || event.type == "execute_error",
              let output = event.output, !output.isEmpty else { return }

        let text = "Tool \(event.toolName): \(output)"
        let vec = (try? await embedder.generateEmbedding(for: text)) ?? []
        guard !vec.isEmpty else { return }

        try? await vectorStoreService?.addEntry(
            text: String(text.prefix(500)),
            vector: vec,
            source: event.toolName,
            category: event.conversationId
        )
    }
}
