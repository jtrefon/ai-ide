import SwiftUI

struct EditorTabBar: View {
    let tabs: [EditorPaneStateManager.EditorTab]
    let activeTabID: UUID?
    let onActivate: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if tabs.isEmpty {
                        Text(NSLocalizedString("editor.untitled", comment: ""))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(tabs) { tab in
                            TabBarButton(
                                tab: tab,
                                isActive: tab.id == activeTabID,
                                onActivate: { onActivate(tab.id) },
                                onClose: { onClose(tab.id) },
                                onFocus: onFocus
                            )
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(height: 32)
            .background(.windowBackground)

            Divider()
        }
    }
}

private struct TabBarButton: View {
    let tab: EditorPaneStateManager.EditorTab
    let isActive: Bool
    let onActivate: () -> Void
    let onClose: () -> Void
    let onFocus: () -> Void

    @State private var isHovered = false

    private var displayName: String {
        URL(fileURLWithPath: tab.filePath).lastPathComponent
            + (tab.isDirty ? " •" : "")
    }

    var body: some View {
        Button(action: {
            onFocus()
            onActivate()
        }) {
            HStack(spacing: 4) {
                Text(displayName)
                    .lineLimit(1)
                    .font(.body)
                    .foregroundColor(isActive ? .primary : .secondary)

                Button(action: {
                    onFocus()
                    onClose()
                }) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 5))
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered
                            ? Color(nsColor: .controlBackgroundColor).opacity(0.15)
                            : Color.clear)
                        .strokeBorder(
                            Color(nsColor: .separatorColor).opacity(isHovered ? 0.35 : 0.2),
                            lineWidth: 1
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}
