import Foundation

@MainActor
final class SessionManager: ObservableObject {

    struct SessionSnapshot: Codable {
        let messages: [ChatMessage]
        let mode: AIMode
        let input: String
        let livePreview: String
        let liveStatusPreview: String
    }

    @Published private(set) var conversationTabs: [ConversationTabItem] = []

    private let historyCoordinator: ChatHistoryCoordinator
    private var projectRoot: URL
    private var currentSessionId: String
    private var conversationSessionOrder: [String]
    private var conversationSessionSnapshots: [String: SessionSnapshot]

    private static let orderDefaultsKey = "SessionManager.sessionOrder"
    private static let selectedIdDefaultsKey = "SessionManager.selectedId"

    init(
        historyCoordinator: ChatHistoryCoordinator,
        projectRoot: URL
    ) {
        self.historyCoordinator = historyCoordinator
        self.projectRoot = projectRoot
        let loadedOrder: [String]
        let loadedSelectedId: String
        if let savedOrder = Self.loadSessionOrder(),
           let savedSelectedId = Self.loadSelectedId(),
           !savedOrder.isEmpty {
            loadedOrder = savedOrder
            loadedSelectedId = savedSelectedId
        } else {
            loadedOrder = [historyCoordinator.currentConversationId]
            loadedSelectedId = historyCoordinator.currentConversationId
        }
        self.currentSessionId = loadedSelectedId
        self.conversationSessionOrder = loadedOrder
        self.conversationSessionSnapshots = [:]
        for sessionId in loadedOrder {
            if let snapshot = Self.loadSnapshot(sessionId: sessionId, projectRoot: projectRoot) {
                conversationSessionSnapshots[sessionId] = snapshot
            }
        }
        if conversationSessionSnapshots[currentSessionId] == nil {
            conversationSessionSnapshots[currentSessionId] = SessionSnapshot(
                messages: historyCoordinator.messages,
                mode: .chat,
                input: "",
                livePreview: "",
                liveStatusPreview: ""
            )
        }
        refreshTabs()
    }

    var selectedId: String {
        currentSessionId
    }

    // MARK: - Tab Management

    private func refreshTabs() {
        conversationTabs = conversationSessionOrder.enumerated().map { index, id in
            ConversationTabItem(id: id, title: "Chat \(index + 1)")
        }
    }

    // MARK: - Snapshot Management

    func saveSnapshot(input: String, livePreview: String, liveStatusPreview: String, mode: AIMode) {
        let snapshot = SessionSnapshot(
            messages: historyCoordinator.messages,
            mode: mode,
            input: input,
            livePreview: livePreview,
            liveStatusPreview: liveStatusPreview
        )
        conversationSessionSnapshots[currentSessionId] = snapshot
        Self.saveSnapshot(sessionId: currentSessionId, snapshot: snapshot, projectRoot: projectRoot)
        Self.saveSessionOrder(conversationSessionOrder)
        Self.saveSelectedId(currentSessionId)
    }

    func restoreSession(_ sessionId: String, input: inout String, livePreview: inout String,
                        liveStatusPreview: inout String, mode: inout AIMode) {
        let snapshot = conversationSessionSnapshots[sessionId] ?? SessionSnapshot(
            messages: [],
            mode: .chat,
            input: "",
            livePreview: "",
            liveStatusPreview: ""
        )
        currentSessionId = sessionId
        historyCoordinator.switchConversation(to: sessionId, projectRoot: projectRoot)
        historyCoordinator.replaceAllMessages(with: snapshot.messages)
        mode = snapshot.mode
        input = snapshot.input
        livePreview = snapshot.livePreview
        liveStatusPreview = snapshot.liveStatusPreview
    }

    // MARK: - Session Lifecycle

    func startNew(input: inout String, livePreview: inout String, liveStatusPreview: inout String,
                  mode: inout AIMode) -> String {
        let oldConversationId = currentSessionId
        let newConversationId = UUID().uuidString
        conversationSessionOrder.append(newConversationId)
        let snapshot = SessionSnapshot(
            messages: [],
            mode: mode,
            input: "",
            livePreview: "",
            liveStatusPreview: ""
        )
        conversationSessionSnapshots[newConversationId] = snapshot
        Self.saveSnapshot(sessionId: newConversationId, snapshot: snapshot, projectRoot: projectRoot)
        restoreSession(newConversationId, input: &input, livePreview: &livePreview,
                       liveStatusPreview: &liveStatusPreview, mode: &mode)
        refreshTabs()
        Self.saveSessionOrder(conversationSessionOrder)
        Self.saveSelectedId(currentSessionId)
        return oldConversationId
    }

    func switchTo(id: String, input: inout String, livePreview: inout String,
                  liveStatusPreview: inout String, mode: inout AIMode) -> Bool {
        guard id != currentSessionId, conversationSessionSnapshots[id] != nil else { return false }
        restoreSession(id, input: &input, livePreview: &livePreview,
                       liveStatusPreview: &liveStatusPreview, mode: &mode)
        refreshTabs()
        Self.saveSelectedId(currentSessionId)
        return true
    }

    func close(id: String, input: inout String, livePreview: inout String,
               liveStatusPreview: inout String, mode: inout AIMode) -> Bool {
        guard conversationSessionOrder.count > 1 else { return false }
        guard let closingIndex = conversationSessionOrder.firstIndex(of: id) else { return false }

        conversationSessionOrder.remove(at: closingIndex)
        conversationSessionSnapshots[id] = nil
        Self.deleteSnapshot(sessionId: id, projectRoot: projectRoot)

        if id == currentSessionId {
            let fallbackIndex = min(closingIndex, conversationSessionOrder.count - 1)
            let fallbackId = conversationSessionOrder[fallbackIndex]
            restoreSession(fallbackId, input: &input, livePreview: &livePreview,
                           liveStatusPreview: &liveStatusPreview, mode: &mode)
        }

        refreshTabs()
        Self.saveSessionOrder(conversationSessionOrder)
        Self.saveSelectedId(currentSessionId)
        return true
    }

    func resetAll(input: inout String, livePreview: inout String, liveStatusPreview: inout String) {
        input = ""
        livePreview = ""
        liveStatusPreview = ""
    }

    func updateProjectRoot(_ newRoot: URL, input: inout String, livePreview: inout String,
                           liveStatusPreview: inout String, mode: inout AIMode) {
        projectRoot = newRoot

        let migratedSessionId = historyCoordinator.currentConversationId
        currentSessionId = migratedSessionId
        conversationSessionOrder = [migratedSessionId]
        let snapshot = SessionSnapshot(
            messages: historyCoordinator.messages,
            mode: mode,
            input: input,
            livePreview: livePreview,
            liveStatusPreview: liveStatusPreview
        )
        conversationSessionSnapshots = [migratedSessionId: snapshot]
        Self.saveSnapshot(sessionId: migratedSessionId, snapshot: snapshot, projectRoot: projectRoot)
        refreshTabs()
        Self.saveSessionOrder(conversationSessionOrder)
        Self.saveSelectedId(currentSessionId)
    }

    // MARK: - Disk Persistence

    private static func sessionsDirectory(projectRoot: URL) -> URL {
        projectRoot
            .appendingPathComponent(AppConstantsFileSystem.projectDirName, isDirectory: true)
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func snapshotURL(sessionId: String, projectRoot: URL) -> URL {
        sessionsDirectory(projectRoot: projectRoot)
            .appendingPathComponent("\(sessionId).json")
    }

    private static func saveSnapshot(sessionId: String, snapshot: SessionSnapshot, projectRoot: URL) {
        let dir = sessionsDirectory(projectRoot: projectRoot)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = snapshotURL(sessionId: sessionId, projectRoot: projectRoot)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func loadSnapshot(sessionId: String, projectRoot: URL) -> SessionSnapshot? {
        let url = snapshotURL(sessionId: sessionId, projectRoot: projectRoot)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private static func deleteSnapshot(sessionId: String, projectRoot: URL) {
        let url = snapshotURL(sessionId: sessionId, projectRoot: projectRoot)
        try? FileManager.default.removeItem(at: url)
    }

    private static func loadSessionOrder() -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: orderDefaultsKey),
              let order = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return order
    }

    private static func saveSessionOrder(_ order: [String]) {
        if let data = try? JSONEncoder().encode(order) {
            UserDefaults.standard.set(data, forKey: orderDefaultsKey)
        }
    }

    private static func loadSelectedId() -> String? {
        UserDefaults.standard.string(forKey: selectedIdDefaultsKey)
    }

    private static func saveSelectedId(_ id: String) {
        UserDefaults.standard.set(id, forKey: selectedIdDefaultsKey)
    }
}
