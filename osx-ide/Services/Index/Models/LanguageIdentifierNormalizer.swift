import Foundation

public enum LanguageIdentifierNormalizer {
    public static func normalize(_ raw: String) -> String {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.hasPrefix("language_") {
            normalized.removeFirst("language_".count)
        }
        if normalized.hasPrefix(".") {
            normalized.removeFirst()
        }

        switch normalized {
        case "js":
            return "javascript"
        case "ts":
            return "typescript"
        case "py":
            return "python"
        default:
            return normalized
        }
    }
}
