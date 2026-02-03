import Foundation

public struct SidebarVisibilityChangedEvent: Event {
    public let isVisible: Bool

    public init(isVisible: Bool) {
        self.isVisible = isVisible
    }
}
