import SwiftUI

/// A minimal AppKit bridge to access the hosting NSWindow.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor [weak view] in
            guard let view else { return }
            guard let window = view.window else { return }
            context.coordinator.resolveIfNeeded(window: window, onResolve: onResolve)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor [weak nsView] in
            guard let nsView else { return }
            guard let window = nsView.window else { return }
            context.coordinator.resolve(window: window, onResolve: onResolve)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var resolvedWindow: NSWindow?

        // Initial binding path.
        func resolveIfNeeded(window: NSWindow, onResolve: (NSWindow) -> Void) {
            guard resolvedWindow !== window else { return }
            resolvedWindow = window
            onResolve(window)
        }

        // Update path: re-apply window configuration each render pass.
        func resolve(window: NSWindow, onResolve: (NSWindow) -> Void) {
            resolvedWindow = window
            onResolve(window)
        }
    }
}
