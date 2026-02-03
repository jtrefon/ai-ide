import Foundation

public struct AIEnrichmentCompletedEvent: Event {
    public let processedCount: Int
    public let duration: TimeInterval

    public init(processedCount: Int, duration: TimeInterval) {
        self.processedCount = processedCount
        self.duration = duration
    }
}
