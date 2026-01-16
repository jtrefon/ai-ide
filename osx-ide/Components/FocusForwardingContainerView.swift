import AppKit

final class FocusForwardingContainerView: NSView {
    var onFocusRequested: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocusRequested?()
        super.mouseDown(with: event)
    }
}
