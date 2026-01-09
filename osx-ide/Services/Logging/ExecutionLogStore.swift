import Foundation

public actor ExecutionLogStore {
    public static let shared = ExecutionLogStore()

    private let iso = ISO8601DateFormatter()

    private var projectRoot: URL?

    public func setProjectRoot(_ root: URL) {
        self.projectRoot = root
    }

    private func conversationDirectory(conversationId: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        let base = appSupport.appendingPathComponent("osx-ide/Logs", isDirectory: true)
        return base.appendingPathComponent("conversations", isDirectory: true)
            .appendingPathComponent(conversationId, isDirectory: true)
    }

    private func projectConversationDirectory(conversationId: String) -> URL? {
        guard let projectRoot else { return nil }
        return projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)
            .appendingPathComponent(conversationId, isDirectory: true)
    }

    private func executionLogFileURL(conversationId: String) -> URL {
        conversationDirectory(conversationId: conversationId).appendingPathComponent("executions.ndjson")
    }

    private func projectExecutionLogFileURL(conversationId: String) -> URL? {
        projectConversationDirectory(conversationId: conversationId)?.appendingPathComponent("executions.ndjson")
    }

    public func append(_ request: ExecutionLogAppendRequest) async {
        let sessionId = await AppLogger.shared.currentSessionId()
        let conversationId = request.context.conversationId ?? "unknown"
        
        let header = ExecutionLogEventHeader(
            ts: iso.string(from: Date()),
            session: sessionId,
            conversationId: request.context.conversationId,
            tool: request.context.tool
        )
        let event = ExecutionLogEvent(
            header: header,
            toolCallId: request.toolCallId,
            type: request.type,
            data: request.data
        )

        do {
            let dir = conversationDirectory(conversationId: conversationId)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = executionLogFileURL(conversationId: conversationId)
            let json = try JSONEncoder().encode(event)
            var line = Data()
            line.append(json)
            line.append(Data("\n".utf8))

            try append(line: line, to: fileURL)

            if let projectDir = projectConversationDirectory(conversationId: conversationId), let projectFileURL = projectExecutionLogFileURL(conversationId: conversationId) {
                try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
                try append(line: line, to: projectFileURL)
            }
        } catch {
            _ = error
        }
    }

    private func append(line: Data, to fileURL: URL) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: fileURL, options: [.atomic])
        }
    }
}
