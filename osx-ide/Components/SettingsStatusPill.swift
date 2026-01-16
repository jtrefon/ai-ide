import SwiftUI

struct SettingsStatusPill: View {
    let status: OpenRouterSettingsViewModel.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(status.message)
                .font(.system(size: AppConstants.Settings.statusTextSize))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
        )
    }

    private var statusColor: Color {
        switch status.kind {
        case .idle:
            return Color.gray.opacity(0.6)
        case .loading:
            return Color.blue.opacity(0.8)
        case .success:
            return Color.green.opacity(0.8)
        case .warning:
            return Color.orange.opacity(0.9)
        case .error:
            return Color.red.opacity(0.9)
        }
    }
}
