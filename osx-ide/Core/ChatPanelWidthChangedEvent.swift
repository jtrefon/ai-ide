import Foundation

public struct ChatPanelWidthChangedEvent: Event {
    public let width: Double

    public init(width: Double) {
        self.width = width
    }
}
