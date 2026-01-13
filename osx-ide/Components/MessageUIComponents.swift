//
//  MessageUIComponents.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import SwiftUI
import Foundation

/// UI components for message display
struct MessageUIComponents {
    
    // MARK: - Corner Radius Components
    
    struct RectCorner: OptionSet, Sendable {
        let rawValue: Int
        static let topLeft = RectCorner(rawValue: 1 << 0)
        static let topRight = RectCorner(rawValue: 1 << 1)
        static let bottomRight = RectCorner(rawValue: 1 << 2)
        static let bottomLeft = RectCorner(rawValue: 1 << 3)
        static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }
    
    struct RoundedCorner: Shape {
        var radius: CGFloat = .infinity
        var corners: RectCorner = .allCorners

        func path(in rect: CGRect) -> Path {
            var path = Path()
            
            let p1 = CGPoint(x: rect.minX, y: rect.minY)
            let p2 = CGPoint(x: rect.maxX, y: rect.minY)
            let p3 = CGPoint(x: rect.maxX, y: rect.maxY)
            let p4 = CGPoint(x: rect.minX, y: rect.maxY)
            
            // Start from top-left
            if corners.contains(.topLeft) {
                path.move(to: CGPoint(x: p1.x + radius, y: p1.y))
            } else {
                path.move(to: p1)
            }
            
            // Top edge to top-right
            if corners.contains(.topRight) {
                path.addLine(to: CGPoint(x: p2.x - radius, y: p2.y))
                path.addArc(
                    center: CGPoint(x: p2.x - radius, y: p2.y + radius),
                    radius: radius,
                    startAngle: Angle(degrees: -90),
                    endAngle: Angle(degrees: 0),
                    clockwise: false
                )
            } else {
                path.addLine(to: p2)
            }
            
            // Right edge to bottom-right
            if corners.contains(.bottomRight) {
                path.addLine(to: CGPoint(x: p3.x - radius, y: p3.y))
                path.addArc(
                    center: CGPoint(x: p3.x - radius, y: p3.y - radius),
                    radius: radius,
                    startAngle: Angle(degrees: 0),
                    endAngle: Angle(degrees: 90),
                    clockwise: false
                )
            } else {
                path.addLine(to: p3)
            }
            
            // Bottom edge to bottom-left
            if corners.contains(.bottomLeft) {
                path.addLine(to: CGPoint(x: p4.x + radius, y: p4.y))
                path.addArc(
                    center: CGPoint(x: p4.x + radius, y: p4.y - radius),
                    radius: radius,
                    startAngle: Angle(degrees: 90),
                    endAngle: Angle(degrees: 180),
                    clockwise: false
                )
            } else {
                path.addLine(to: p4)
            }
            
            // Left edge back to top-left
            if corners.contains(.topLeft) {
                path.addLine(to: CGPoint(x: p1.x + radius, y: p1.y))
                path.addArc(
                    center: CGPoint(x: p1.x + radius, y: p1.y + radius),
                    radius: radius,
                    startAngle: Angle(degrees: 180),
                    endAngle: Angle(degrees: 270),
                    clockwise: false
                )
            } else {
                path.addLine(to: p1)
            }
            
            return path
        }
    }
}

// MARK: - View Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: MessageUIComponents.RectCorner) -> some View {
        clipShape(MessageUIComponents.RoundedCorner(radius: radius, corners: corners))
    }
}
