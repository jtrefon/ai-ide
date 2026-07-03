import Foundation

public struct VectorStoreStatusChangedEvent: Event {
    public let entryCount: Int
    public let isLoaded: Bool

    public init(entryCount: Int, isLoaded: Bool) {
        self.entryCount = entryCount
        self.isLoaded = isLoaded
    }
}
