import SwiftUI

struct CapsuleDropdownLabel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: AppConstants.Layout.spacingXS) {
            content()
            Image(systemName: "chevron.down")
                .font(.system(size: AppConstants.Layout.controlChevronSize))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppConstants.Layout.controlHPadding)
        .frame(height: AppConstants.Layout.controlHeight)
    }
}
