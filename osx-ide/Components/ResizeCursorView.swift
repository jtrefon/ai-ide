import SwiftUI
import AppKit

struct ResizeCursorView: NSViewRepresentable {
    let cursor: NSCursor

    init(cursor: NSCursor = .resizeUpDown) {
        self.cursor = cursor
    }

    func makeNSView(context _: Context) -> NSView {
        CursorRectNSView(cursor: cursor)
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        _ = nsView
    }
}
