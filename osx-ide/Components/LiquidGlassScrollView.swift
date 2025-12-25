import SwiftUI
import AppKit

/// A stable, native NSScrollView wrapper that provides a "Liquid Glass" scrollbar.
/// Refactored to NSViewRepresentable to eliminate SwiftUI layout loops and crashes.
struct LiquidGlassScrollView<Content: View>: NSViewRepresentable {
    let axes: Axis.Set
    let showsIndicators: Bool
    let scrollToBottomTrigger: Int
    let content: Content

    init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = false, scrollToBottomTrigger: Int = 0, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.scrollToBottomTrigger = scrollToBottomTrigger
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = axes.contains(.vertical)
        scrollView.hasHorizontalScroller = axes.contains(.horizontal)
        scrollView.autohidesScrollers = !showsIndicators
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.verticalScrollElasticity = .allowed
        
        // Create hosting view
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = axes.contains(.vertical) ? [.width] : []

        scrollView.documentView = hostingView

        // Track bounds changes so we can recompute the hosted content size during live resize.
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.attach(scrollView: scrollView)
        
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hostingView = scrollView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content

            if axes.contains(.vertical) {
                // Force layout to compute the true content height, then set the frame.
                // This ensures the scroll view knows the full document height without cutoff.
                context.coordinator.updateHostedSize()
            }
            
            // Check for scroll to bottom trigger
            if context.coordinator.lastTrigger != scrollToBottomTrigger {
                context.coordinator.lastTrigger = scrollToBottomTrigger
                
                // Allow some time for layout to finish before scrolling
                DispatchQueue.main.async {
                    let contentView = scrollView.contentView
                    guard let documentView = scrollView.documentView else { return }
                    let bottomY = max(0, documentView.frame.height - contentView.bounds.height)
                    contentView.scroll(to: NSPoint(x: 0, y: bottomY))
                    scrollView.reflectScrolledClipView(contentView)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var lastTrigger: Int = 0
        private weak var scrollView: NSScrollView?
        private weak var hostingView: NSView?
        private var boundsObserver: NSObjectProtocol?

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func attach(scrollView: NSScrollView) {
            self.scrollView = scrollView
            self.hostingView = scrollView.documentView

            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateHostedSize()
            }

            updateHostedSize()
        }

        func updateHostedSize() {
            guard let scrollView, let hostingView else { return }
            let targetWidth = scrollView.contentView.bounds.width
            hostingView.frame.size.width = targetWidth
            hostingView.layoutSubtreeIfNeeded()
            hostingView.frame.size.height = hostingView.fittingSize.height
        }
    }
}
