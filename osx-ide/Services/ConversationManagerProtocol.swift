import Foundation

public struct ConversationTabItem: Identifiable, Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct ConversationProviderIssueState: Equatable {
    public let providerName: String
    public let issueType: String
    public let statusCode: Int?
    public let message: String
    public let cooldownUntil: Date?

    public init(
        providerName: String,
        issueType: String,
        statusCode: Int?,
        message: String,
        cooldownUntil: Date?
    ) {
        self.providerName = providerName
        self.issueType = issueType
        self.statusCode = statusCode
        self.message = message
        self.cooldownUntil = cooldownUntil
    }
}

@MainActor
public protocol ConversationManagerProtocol: AnyObject, StatePublisherProtocol {
    var messages: [ChatMessage] { get }
    var conversationTabs: [ConversationTabItem] { get }
    var currentInput: String { get set }
    var isSending: Bool { get }
    var error: String? { get }
    var currentMode: AIMode { get set }
    var currentConversationId: String { get }
    var liveModelOutputPreview: String { get }
    var liveModelOutputStatusPreview: String { get }
    var isLiveModelOutputPreviewVisible: Bool { get }
    var providerIssue: ConversationProviderIssueState? { get }

    func sendMessage()
    func sendMessage(context: String?)
    func clearConversation()
    func startNewConversation()
    func switchConversation(to id: String)
    func closeConversation(id: String)
    func stopGeneration()
    func updateProjectRoot(_ root: URL)
}
