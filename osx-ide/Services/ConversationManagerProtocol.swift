import Foundation

@MainActor
public protocol ConversationManagerProtocol: AnyObject, StatePublisherProtocol {
    var messages: [ChatMessage] { get }
    var currentInput: String { get set }
    var isSending: Bool { get }
    var error: String? { get }
    var currentMode: AIMode { get set }
    var currentConversationId: String { get }
    var liveModelOutputPreview: String { get }
    var liveModelOutputStatusPreview: String { get }
    var isLiveModelOutputPreviewVisible: Bool { get }

    func sendMessage()
    func sendMessage(context: String?)
    func clearConversation()
    func startNewConversation()
    func stopGeneration()
    func updateProjectRoot(_ root: URL)
}
