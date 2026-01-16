import Foundation

struct OpenRouterModel: Identifiable, Decodable, Hashable {
    let id: String
    let name: String?

    var displayName: String {
        name ?? id
    }
}
