import Foundation

public struct SidebarWidthChangedEvent: Event {
    public let width: Double

    public init(width: Double) {
        self.width = width
    }
}
