import Foundation

#if canImport(MLX)
import MLX
#endif

public protocol WiredMemoryPolicy: Sendable {
    func limit(baseline: Int, activeSizes: [Int]) -> Int
    func canAdmit(baseline: Int, activeSizes: [Int], newSize: Int) -> Bool
}

extension WiredMemoryPolicy {
    public func canAdmit(baseline: Int, activeSizes: [Int], newSize: Int) -> Bool {
        true
    }
}

public enum WiredMemoryTicketKind: Sendable {
    case active
    case reservation
}

public struct WiredMemoryTicket: Sendable, Identifiable {
    public let id: UUID
    public let size: Int
    public let policy: any WiredMemoryPolicy
    public let kind: WiredMemoryTicketKind

    public init(
        id: UUID = UUID(),
        size: Int,
        policy: any WiredMemoryPolicy,
        kind: WiredMemoryTicketKind = .active
    ) {
        self.id = id
        self.size = size
        self.policy = policy
        self.kind = kind
    }

    public static func withWiredLimit<T>(
        _ ticket: WiredMemoryTicket,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await operation()
    }

    public func withWiredLimit<T>(
        operation: () async throws -> T
    ) async rethrows -> T {
        try await operation()
    }
}

#if canImport(MLX)
extension GPU {
    public static func maxRecommendedWorkingSetBytes() -> Int? {
        nil
    }
}
#endif
