import AppKit

@MainActor
final class NativeTerminalTextView: NSTextView {
    weak var inputDelegate: NativeTerminalEmbedder?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let characters = event.characters {
            inputDelegate?.forwardTerminalInput(characters)
        }
    }

    override func doCommand(by selector: Selector) {
        guard let inputDelegate else { return }
        _ = inputDelegate.handleTerminalCommand(selector)
    }
}
