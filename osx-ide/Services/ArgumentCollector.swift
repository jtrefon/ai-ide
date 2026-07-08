import Foundation

actor ArgumentCollector {
    private var buffer: String = ""

    func reset() {
        buffer = ""
    }

    func append(_ chunk: String) {
        buffer += chunk
    }

    func collect() -> [String: ToolValue]? {
        guard !buffer.isEmpty else { return nil }
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsed = parseJSONObject(trimmed) {
            return ToolValue.from(dictionary: parsed)
        }

        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            let extracted = String(trimmed[start...end])
            if let parsed = parseJSONObject(extracted) {
                return ToolValue.from(dictionary: parsed)
            }
        }

        return nil
    }

    var currentBuffer: String { buffer }

    private func parseJSONObject(_ candidate: String) -> [String: Any]? {
        guard let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}

// MARK: - Non-streaming variant (for already-assembled argument strings)

struct ArgumentParser {
    static func parse(_ raw: String) -> [String: ToolValue]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ToolValue.from(dictionary: object)
        }

        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            let extracted = String(trimmed[start...end])
            if let data = extracted.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return ToolValue.from(dictionary: object)
            }
        }

        return nil
    }
}
