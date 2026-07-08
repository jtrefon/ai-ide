import Foundation

actor LogBus {
    struct Config: Sendable {
        let maxBatchSize: Int
        let flushInterval: Duration
        static let `default` = Config(maxBatchSize: 100, flushInterval: .milliseconds(100))
    }

    private let config: Config
    private var buffer: [ToolLogEvent] = []
    private var flushTask: Task<Void, Never>?

    init(config: Config = .default) {
        self.config = config
    }

    func emit(_ event: ToolLogEvent) {
        buffer.append(event)
        if buffer.count >= config.maxBatchSize {
            flush()
        } else if flushTask == nil {
            startFlushTimer()
        }
    }

    func flush() {
        let batch = buffer
        buffer.removeAll()
        guard !batch.isEmpty else { return }
        Task { await writeBatch(batch) }
    }

    private func startFlushTimer() {
        flushTask = Task {
            try? await Task.sleep(for: config.flushInterval)
            flush()
            flushTask = nil
        }
    }

    private func writeBatch(_ events: [ToolLogEvent]) async {
        for event in events {
            await AIToolTraceLogger.shared.log(type: event.type, data: event.metadata)
        }
    }
}

struct ToolLogEvent: @unchecked Sendable {
    let type: String
    let toolCallId: String
    let toolName: String
    let targetPath: String?
    let metadata: [String: Any]
    let timestamp: Date

    static func start(toolCallId: String, toolName: String, targetPath: String?) -> ToolLogEvent {
        ToolLogEvent(type: "tool.execute_start", toolCallId: toolCallId, toolName: toolName,
                     targetPath: targetPath, metadata: ["tool": toolName, "targetPath": targetPath as Any], timestamp: Date())
    }

    static func success(toolCallId: String, toolName: String, resultLength: Int) -> ToolLogEvent {
        ToolLogEvent(type: "tool.execute_success", toolCallId: toolCallId, toolName: toolName,
                     targetPath: nil, metadata: ["tool": toolName, "resultLength": resultLength], timestamp: Date())
    }

    static func error(toolCallId: String, toolName: String, error: String) -> ToolLogEvent {
        ToolLogEvent(type: "tool.execute_error", toolCallId: toolCallId, toolName: toolName,
                     targetPath: nil, metadata: ["tool": toolName, "error": error], timestamp: Date())
    }
}
