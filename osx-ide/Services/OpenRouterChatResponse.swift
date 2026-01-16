import Foundation

internal struct OpenRouterChatResponse: Decodable {
    let choices: [OpenRouterChatResponseChoice]
}
