import SwiftUI
import AppKit

struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        CursorRectNSView(cursor: .resizeUpDown)
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        _ = nsView
    }
}
