import Foundation

struct OpenRouterModel: Identifiable, Decodable, Hashable {
    let id: String
    let name: String?
    let contextLength: Int?

    var displayName: String {
        name ?? id
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case contextLength = "context_length"
    }
}
