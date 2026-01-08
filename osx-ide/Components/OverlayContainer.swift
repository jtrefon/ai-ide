import SwiftUI

struct OverlayContainer<Content: View>: View {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    let content: Content

    init(
        isPresented: Binding<Bool>,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(AppConstants.Overlay.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                content
                    .padding(AppConstants.Overlay.hostPadding)
            }
            .transition(.opacity)
        }
    }
}
