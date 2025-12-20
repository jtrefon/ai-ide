import SwiftUI

/// A minimal AppKit bridge to access the hosting NSWindow.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let view, let window = view.window else { return }
            context.coordinator.resolveIfNeeded(window: window, onResolve: onResolve)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView, let window = nsView.window else { return }
            context.coordinator.resolveIfNeeded(window: window, onResolve: onResolve)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var resolvedWindow: NSWindow?

        func resolveIfNeeded(window: NSWindow, onResolve: (NSWindow) -> Void) {
            guard resolvedWindow !== window else { return }
            resolvedWindow = window
            onResolve(window)
        }
    }
}
