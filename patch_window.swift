import Foundation
import AppKit

extension NSWindow {
    func clampFrameToScreen(desiredFrame: CGRect) -> CGRect {
        guard let screen = self.screen else { return desiredFrame }
        let visible = screen.visibleFrame
        var newFrame = desiredFrame
        
        // Clamp height
        if newFrame.height > visible.height {
            newFrame.size.height = visible.height
        }
        
        // Clamp Y (bottom must not go below visible.minY)
        if newFrame.minY < visible.minY {
            newFrame.origin.y = visible.minY
        }
        
        // Clamp X
        if newFrame.minX < visible.minX {
            newFrame.origin.x = visible.minX
        } else if newFrame.maxX > visible.maxX {
            newFrame.origin.x = visible.maxX - newFrame.width
        }
        
        // Clamp Top (top must not go above visible.maxY)
        if newFrame.maxY > visible.maxY {
            newFrame.origin.y = visible.maxY - newFrame.height
        }
        
        return newFrame
    }
}
