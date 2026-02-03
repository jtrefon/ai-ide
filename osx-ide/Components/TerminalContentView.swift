import SwiftUI
import AppKit

/// NSViewRepresentable that properly embeds the terminal view
struct TerminalContentView: NSViewRepresentable {
    @ObservedObject var embedder: NativeTerminalEmbedder
    @Binding var currentDirectory: URL?
    var fontSize: Double
    var fontFamily: String

    func makeNSView(context: Context) -> NSView {
        let embedderRef = embedder
        let containerView = FocusForwardingContainerView()
        containerView.onFocusRequested = {
            embedderRef.focusTerminal()
        }
        containerView.wantsLayer = true

        context.coordinator.scheduleEmbed(
            into: containerView,
            embedder: embedder,
            configuration: TerminalContentViewCoordinator.TerminalEmbedConfiguration(
                directory: currentDirectory,
                fontSize: fontSize,
                fontFamily: fontFamily
            )
        )

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let containerView = nsView as? FocusForwardingContainerView {
            let embedderRef = embedder
            containerView.onFocusRequested = {
                embedderRef.focusTerminal()
            }
        }

        context.coordinator.scheduleEmbed(
            into: nsView,
            embedder: embedder,
            configuration: TerminalContentViewCoordinator.TerminalEmbedConfiguration(
                directory: currentDirectory,
                fontSize: fontSize,
                fontFamily: fontFamily
            )
        )
    }

    func makeCoordinator() -> TerminalContentViewCoordinator {
        TerminalContentViewCoordinator()
    }
}
