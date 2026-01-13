import SwiftUI

struct OverlayCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppConstants.Overlay.containerPadding)
            .background(.regularMaterial)
            .cornerRadius(AppConstants.Overlay.containerCornerRadius)
            .shadow(radius: AppConstants.Overlay.containerShadowRadius)
    }
}

struct OverlayScaffold<Content: View>: View {
    let title: String
    let placeholder: String
    @Binding var query: String
    let textFieldMinWidth: CGFloat
    let showsProgress: Bool
    let onSubmit: () -> Void
    let onClose: () -> Void
    private let content: Content

    init(
        title: String,
        placeholder: String,
        query: Binding<String>,
        textFieldMinWidth: CGFloat,
        showsProgress: Bool,
        onSubmit: @escaping () -> Void,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.placeholder = placeholder
        self._query = query
        self.textFieldMinWidth = textFieldMinWidth
        self.showsProgress = showsProgress
        self.onSubmit = onSubmit
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        OverlayCard {
            VStack(spacing: 12) {
                OverlayHeaderView(
                    title: title,
                    placeholder: placeholder,
                    query: $query,
                    textFieldMinWidth: textFieldMinWidth,
                    showsProgress: showsProgress,
                    onSubmit: onSubmit,
                    onClose: onClose
                )

                content
            }
        }
    }
}

struct OverlayHeaderView: View {
    let title: String
    let placeholder: String
    @Binding var query: String
    let textFieldMinWidth: CGFloat
    let showsProgress: Bool
    let onSubmit: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)

            TextField(placeholder, text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: textFieldMinWidth)
                .onSubmit {
                    onSubmit()
                }

            if showsProgress {
                ProgressView()
                    .scaleEffect(0.75)
            }

            Button(NSLocalizedString("common.close", comment: "")) {
                onClose()
            }
        }
    }
}
