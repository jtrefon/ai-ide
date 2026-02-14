import Foundation

actor ConversationPlanStore {
    static let shared = ConversationPlanStore()

    private var projectRoot: URL?
    private var cache: [String: String] = [:]
    private var accessOrder: [String] = []
    private let maxCachedPlans = 5

    func setProjectRoot(_ root: URL) {
        self.projectRoot = root
    }

    func get(conversationId: String) -> String? {
        if let cached = cache[conversationId] {
            touchAccessOrder(conversationId)
            return cached
        }
        guard let url = planFileURL(conversationId: conversationId),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        storeCacheEntry(conversationId: conversationId, plan: text)
        return text
    }

    func set(conversationId: String, plan: String) {
        storeCacheEntry(conversationId: conversationId, plan: plan)
        guard let url = planFileURL(conversationId: conversationId) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try plan.data(using: .utf8)?.write(to: url, options: [.atomic])
        } catch {
        }
    }

    private func storeCacheEntry(conversationId: String, plan: String) {
        cache[conversationId] = plan
        touchAccessOrder(conversationId)
        evictIfNeeded()
    }

    private func touchAccessOrder(_ conversationId: String) {
        accessOrder.removeAll { $0 == conversationId }
        accessOrder.append(conversationId)
    }

    private func evictIfNeeded() {
        while cache.count > maxCachedPlans, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
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
