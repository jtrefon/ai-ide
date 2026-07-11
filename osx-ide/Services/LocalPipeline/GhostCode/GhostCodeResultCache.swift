import Foundation

actor GhostCodeResultCache {
    struct Key: Hashable {
        let prefixTail: String
        let suffixHead: String
    }

    struct Entry {
        let presentation: InlineSuggestionPresentation
        let createdAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private let ttl: TimeInterval = 5.0

    func lookup(prefix: String, suffix: String) -> InlineSuggestionPresentation? {
        let key = makeKey(prefix: prefix, suffix: suffix)
        guard let entry = entries[key], Date().timeIntervalSince(entry.createdAt) < ttl else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.presentation
    }

    func store(_ presentation: InlineSuggestionPresentation, prefix: String, suffix: String) {
        let key = makeKey(prefix: prefix, suffix: suffix)
        entries[key] = Entry(presentation: presentation, createdAt: Date())
    }

    func invalidate() {
        entries.removeAll()
    }

    private func makeKey(prefix: String, suffix: String) -> Key {
        let tail = String(prefix.suffix(200))
        let head = String(suffix.prefix(200))
        return Key(prefixTail: tail, suffixHead: head)
    }
}
