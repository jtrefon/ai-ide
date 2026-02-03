import SwiftUI

extension View {
    func cornerRadius(_ radius: CGFloat, corners: MessageUIComponents.RectCorner) -> some View {
        clipShape(MessageUIComponents.RoundedCorner(radius: radius, corners: corners))
    }
}
