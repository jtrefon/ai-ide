import Foundation

@MainActor
final class SessionManager: ObservableObject {

    struct SessionSnapshot {
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

    init(
        historyCoordinator: ChatHistoryCoordinator,
        projectRoot: URL
    ) {
        self.historyCoordinator = historyCoordinator
        self.projectRoot = projectRoot
        let initialId = historyCoordinator.currentConversationId
        self.currentSessionId = initialId
        self.conversationSessionOrder = [initialId]
        self.conversationSessionSnapshots = [
            initialId: SessionSnapshot(
                messages: historyCoordinator.messages,
                mode: .chat,
                input: "",
                livePreview: "",
                liveStatusPreview: ""
            )
        ]
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
        conversationSessionSnapshots[currentSessionId] = SessionSnapshot(
            messages: historyCoordinator.messages,
            mode: mode,
            input: input,
            livePreview: livePreview,
            liveStatusPreview: liveStatusPreview
        )
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
        conversationSessionSnapshots[newConversationId] = SessionSnapshot(
            messages: [],
            mode: mode,
            input: "",
            livePreview: "",
            liveStatusPreview: ""
        )
        restoreSession(newConversationId, input: &input, livePreview: &livePreview,
                       liveStatusPreview: &liveStatusPreview, mode: &mode)
        refreshTabs()
        return oldConversationId
    }

    func switchTo(id: String, input: inout String, livePreview: inout String,
                  liveStatusPreview: inout String, mode: inout AIMode) -> Bool {
        guard id != currentSessionId, conversationSessionSnapshots[id] != nil else { return false }
        restoreSession(id, input: &input, livePreview: &livePreview,
                       liveStatusPreview: &liveStatusPreview, mode: &mode)
        refreshTabs()
        return true
    }

    func close(id: String, input: inout String, livePreview: inout String,
               liveStatusPreview: inout String, mode: inout AIMode) -> Bool {
        guard conversationSessionOrder.count > 1 else { return false }
        guard let closingIndex = conversationSessionOrder.firstIndex(of: id) else { return false }

        conversationSessionOrder.remove(at: closingIndex)
        conversationSessionSnapshots[id] = nil

        if id == currentSessionId {
            let fallbackIndex = min(closingIndex, conversationSessionOrder.count - 1)
            let fallbackId = conversationSessionOrder[fallbackIndex]
            restoreSession(fallbackId, input: &input, livePreview: &livePreview,
                           liveStatusPreview: &liveStatusPreview, mode: &mode)
        }

        refreshTabs()
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
        conversationSessionSnapshots = [
            migratedSessionId: SessionSnapshot(
                messages: historyCoordinator.messages,
                mode: mode,
                input: input,
                livePreview: livePreview,
                liveStatusPreview: liveStatusPreview
            )
        ]
        refreshTabs()
    }
}
