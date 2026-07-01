import Foundation
enum AgentMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case chat = "Chat", coder = "Coder", agent = "Agent"
    var id: String { rawValue }; var isDefault: Bool { self == .coder }
    func isAvailableForModel(_ m: ModelTier) -> Bool {
        switch self { case .chat: return true; case .coder: return m.supportsToolCalling; case .agent: return m == .cloudPowerful }
    }
}
enum ModelTier: String, Sendable, Codable { case localFast, cloudBalanced, cloudPowerful
    var supportsToolCalling: Bool { self != .localFast }
}
