import Foundation

@MainActor
public protocol ConversationManagerProtocol: AnyObject, StatePublisherProtocol {
    var messages: [ChatMessage] { get }
    var currentInput: String { get set }
    var isSending: Bool { get }
    var error: String? { get }
    var currentMode: AIMode { get set }

    func sendMessage()
    func sendMessage(context: String?)
    func clearConversation()
    func updateProjectRoot(_ root: URL)
}
