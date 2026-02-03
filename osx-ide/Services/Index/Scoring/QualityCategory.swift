import Foundation

public enum QualityCategory: String, Codable, CaseIterable, Sendable {
    case readability
    case complexity
    case maintainability
    case correctness
    case architecture
}
