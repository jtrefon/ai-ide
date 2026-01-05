import Foundation

actor ConversationPlanStore {
    static let shared = ConversationPlanStore()

    private var projectRoot: URL?
    private var cache: [String: String] = [:]

    func setProjectRoot(_ root: URL) {
        self.projectRoot = root
    }

    func get(conversationId: String) -> String? {
        if let cached = cache[conversationId] { return cached }
        guard let url = planFileURL(conversationId: conversationId),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        cache[conversationId] = text
        return text
    }

    func set(conversationId: String, plan: String) {
        cache[conversationId] = plan
        guard let url = planFileURL(conversationId: conversationId) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plan.data(using: .utf8)?.write(to: url, options: [.atomic])
        } catch {
        }
    }

    private func planFileURL(conversationId: String) -> URL? {
        guard let projectRoot else { return nil }
        return projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("plans", isDirectory: true)
            .appendingPathComponent("\(conversationId).md")
    }
}
