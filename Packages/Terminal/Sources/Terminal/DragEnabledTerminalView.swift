import AppKit
import SwiftTerm

final class DragEnabledTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .string])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: nil
        ) as? [URL],
              let first = urls.first else { return false }

        let path = first.path
        let escaped: String
        if path.contains(" ") || path.contains("'") || path.contains("(") || path.contains(")") {
            escaped = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        } else {
            escaped = path
        }

        let text = escaped + " "
        if let data = text.data(using: .utf8) {
            let bytes = [UInt8](data)
            process.send(data: bytes[...])
        }
        return true
    }
}
