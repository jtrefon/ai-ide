import Foundation

enum MessageChronology {
    static func sort(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
    }
}
