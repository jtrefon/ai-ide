import Foundation

enum ConversationScopedNDJSONStore {
    static func conversationDirectory(conversationId: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        let base = appSupport.appendingPathComponent("osx-ide/Logs", isDirectory: true)
        return base
            .appendingPathComponent("conversations", isDirectory: true)
            .appendingPathComponent(conversationId, isDirectory: true)
    }

    static func projectConversationDirectory(projectRoot: URL, conversationId: String) -> URL {
        projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)
            .appendingPathComponent(conversationId, isDirectory: true)
    }

    static func appendLine(
        _ line: Data,
        conversationId: String,
        fileName: String,
        projectRoot: URL?
    ) throws {
        let dir = conversationDirectory(conversationId: conversationId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(fileName)
        try NDJSONLogFileWriter.append(line: line, to: fileURL)

        guard let projectRoot else { return }

        let projectDir = projectConversationDirectory(projectRoot: projectRoot, conversationId: conversationId)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectFileURL = projectDir.appendingPathComponent(fileName)
        try NDJSONLogFileWriter.append(line: line, to: projectFileURL)
    }
}
