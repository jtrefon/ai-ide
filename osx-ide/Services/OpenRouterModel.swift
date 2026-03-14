import Foundation

struct OpenRouterModel: Identifiable, Decodable, Hashable {
    struct Pricing: Decodable, Hashable {
        let prompt: String?
        let completion: String?
    }

    let id: String
    let name: String?
    let contextLength: Int?
    let pricing: Pricing?

    var displayName: String {
        name ?? id
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case contextLength = "context_length"
        case pricing
    }
}
