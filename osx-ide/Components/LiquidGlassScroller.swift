import AppKit
import QuartzCore

/// A custom NSScroller subclass that implements the "Liquid Glass" aesthetic.
/// It features a semi-transparent, rounded thumb that appears on hover or scroll.
class LiquidGlassScroller: NSScroller {
    private var trackingArea: NSTrackingArea?
    private var opacity: CGFloat = 0 {
        didSet {
            self.needsDisplay = true
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupScroller()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScroller()
    }
    
    private func setupScroller() {
        self.wantsLayer = true
        // We only want to see our custom knob
        self.scrollerStyle = .overlay
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        animateOpacity(to: 1.0)
    }
    
    override func mouseExited(with event: NSEvent) {
        animateOpacity(to: 0.0)
    }
    
    private func animateOpacity(to value: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().opacity = value
        }
    }
    
    // Disable default background drawing
    override func draw(_ dirtyRect: NSRect) {
        // Do not draw track/background for overlay look
    }
    
    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard knobRect.width > 0 && knobRect.height > 0 else { return }
        
        // Inset slightly for a floating look
        let insetRect = knobRect.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: insetRect.width / 2, yRadius: insetRect.width / 2)
        
        NSGraphicsContext.saveGraphicsState()
        
        // Use a glass-like material color (vibrant, semi-transparent)
        let glassColor = NSColor.textColor.withAlphaComponent(0.3 * opacity)
        glassColor.set()
        path.fill()
        
        // Subtle border
        let borderColor = NSColor.white.withAlphaComponent(0.1 * opacity)
        borderColor.set()
        path.lineWidth = 0.5
        path.stroke()
        
        NSGraphicsContext.restoreGraphicsState()
    }
}
