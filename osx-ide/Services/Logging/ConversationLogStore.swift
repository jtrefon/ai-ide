import Foundation

public struct ConversationLogEvent: Codable, Sendable {
    public let ts: String
    public let session: String
    public let conversationId: String
    public let type: String
    public let data: [String: LogValue]?
}

public actor ConversationLogStore {
    public static let shared = ConversationLogStore()

    private let iso = ISO8601DateFormatter()

    private var projectRoot: URL?

    public func setProjectRoot(_ root: URL) {
        self.projectRoot = root
    }

    public func append(
        conversationId: String,
        type: String,
        data: [String: Any]? = nil
    ) async {
        let sessionId = await AppLogger.shared.currentSessionId()
        let event = ConversationLogEvent(
            ts: iso.string(from: Date()),
            session: sessionId,
            conversationId: conversationId,
            type: type,
            data: data?.mapValues { LogValue.from($0) }
        )

        do {
            let json = try JSONEncoder().encode(event)
            var line = Data()
            line.append(json)
            line.append(Data("\n".utf8))

            try ConversationScopedNDJSONStore.appendLine(
                line,
                conversationId: conversationId,
                fileName: "conversation.ndjson",
                projectRoot: projectRoot
            )
        } catch {
            await CrashReporter.shared.capture(
                error,
                context: CrashReportContext(operation: "ConversationLogStore.append"),
                metadata: ["conversationId": conversationId],
                file: #fileID,
                function: #function,
                line: #line
            )
        }
    }
}
