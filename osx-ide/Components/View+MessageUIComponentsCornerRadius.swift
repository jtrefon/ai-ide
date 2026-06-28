import SwiftUI

extension View {
    func cornerRadius(_ radius: CGFloat, corners: MessageUIComponents.RectCorner) -> some View {
        clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: corners.contains(.topLeft) ? radius : 0,
                bottomLeadingRadius: corners.contains(.bottomLeft) ? radius : 0,
                bottomTrailingRadius: corners.contains(.bottomRight) ? radius : 0,
                topTrailingRadius: corners.contains(.topRight) ? radius : 0
            )
        )
    }
}
