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

            let points = rectCornerPoints(in: rect)
            moveToStart(&path, topLeft: points.topLeft)
            addTopEdge(&path, points: points)
            addRightEdge(&path, points: points)
            addBottomEdge(&path, points: points)
            addLeftEdge(&path, points: points)

            return path
        }

        private struct CornerPoints {
            let topLeft: CGPoint
            let topRight: CGPoint
            let bottomRight: CGPoint
            let bottomLeft: CGPoint
        }

        private func rectCornerPoints(in rect: CGRect) -> CornerPoints {
            CornerPoints(
                topLeft: CGPoint(x: rect.minX, y: rect.minY),
                topRight: CGPoint(x: rect.maxX, y: rect.minY),
                bottomRight: CGPoint(x: rect.maxX, y: rect.maxY),
                bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
            )
        }

        private func moveToStart(_ path: inout Path, topLeft: CGPoint) {
            // Start from top-left
            if corners.contains(.topLeft) {
                path.move(to: CGPoint(x: topLeft.x + radius, y: topLeft.y))
            } else {
                path.move(to: topLeft)
            }
        }

        private func addTopEdge(_ path: inout Path, points: CornerPoints) {
            // Top edge to top-right
            if corners.contains(.topRight) {
                path.addLine(to: CGPoint(x: points.topRight.x - radius, y: points.topRight.y))
                addArc(
                    &path,
                    center: CGPoint(x: points.topRight.x - radius, y: points.topRight.y + radius),
                    startDegrees: -90,
                    endDegrees: 0
                )
            } else {
                path.addLine(to: points.topRight)
            }
        }

        private func addRightEdge(_ path: inout Path, points: CornerPoints) {
            // Right edge to bottom-right
            if corners.contains(.bottomRight) {
                path.addLine(to: CGPoint(x: points.bottomRight.x - radius, y: points.bottomRight.y))
                addArc(
                    &path,
                    center: CGPoint(x: points.bottomRight.x - radius, y: points.bottomRight.y - radius),
                    startDegrees: 0,
                    endDegrees: 90
                )
            } else {
                path.addLine(to: points.bottomRight)
            }
        }

        private func addBottomEdge(_ path: inout Path, points: CornerPoints) {
            // Bottom edge to bottom-left
            if corners.contains(.bottomLeft) {
                path.addLine(to: CGPoint(x: points.bottomLeft.x + radius, y: points.bottomLeft.y))
                addArc(
                    &path,
                    center: CGPoint(x: points.bottomLeft.x + radius, y: points.bottomLeft.y - radius),
                    startDegrees: 90,
                    endDegrees: 180
                )
            } else {
                path.addLine(to: points.bottomLeft)
            }
        }

        private func addLeftEdge(_ path: inout Path, points: CornerPoints) {
            // Left edge back to top-left
            if corners.contains(.topLeft) {
                path.addLine(to: CGPoint(x: points.topLeft.x + radius, y: points.topLeft.y))
                addArc(
                    &path,
                    center: CGPoint(x: points.topLeft.x + radius, y: points.topLeft.y + radius),
                    startDegrees: 180,
                    endDegrees: 270
                )
            } else {
                path.addLine(to: points.topLeft)
            }
        }

        private func addArc(
            _ path: inout Path,
            center: CGPoint,
            startDegrees: Double,
            endDegrees: Double
        ) {
            path.addArc(
                center: center,
                radius: radius,
                startAngle: Angle(degrees: startDegrees),
                endAngle: Angle(degrees: endDegrees),
                clockwise: false
            )
        }
    }
}

// MARK: - View Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: MessageUIComponents.RectCorner) -> some View {
        clipShape(MessageUIComponents.RoundedCorner(radius: radius, corners: corners))
    }
}
