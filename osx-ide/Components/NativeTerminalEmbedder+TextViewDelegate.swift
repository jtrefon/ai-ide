import AppKit

// MARK: - NSTextViewDelegate
extension NativeTerminalEmbedder: NSTextViewDelegate {
    func textView(_ _: NSTextView, doCommandBy _: Selector) -> Bool { false }

    func textView(_ _: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool { false }
}
