import SwiftUI
import AppKit

/// A stable, native NSScrollView wrapper that provides a "Liquid Glass" scrollbar.
/// Refactored to NSViewRepresentable to eliminate SwiftUI layout loops and crashes.
struct LiquidGlassScrollView<Content: View>: NSViewRepresentable {
    let axes: Axis.Set
    let showsIndicators: Bool
    let content: Content
    let scrollToBottomTrigger: Int

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
        
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.documentView = hostingView
        
        // For vertical scrolling, we want the content to match the parent's width
        if axes == [.vertical] {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor)
            ])
        }
        
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hostingView = scrollView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
            
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
    }
}
