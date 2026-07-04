import SwiftUI

struct EditorTabBar: View {
    let tabs: [EditorPaneStateManager.EditorTab]
    let activeTabID: UUID?
    let onActivate: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onFocus: () -> Void

    @State private var hoveredTabID: UUID?

    private let minTabWidth: CGFloat = 80
    private let spacing: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            if tabs.isEmpty {
                HStack {
                    Text(NSLocalizedString("editor.untitled", comment: ""))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    Spacer(minLength: 0)
                }
                .frame(height: 32)
                .background(.thinMaterial)
            } else {
                GeometryReader { geometry in
                    let tabCount = max(tabs.count, 1)
                    let tabWidth = max(
                        minTabWidth,
                        (geometry.size.width - 8 - spacing * CGFloat(tabCount - 1)) / CGFloat(tabCount)
                    )

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            ForEach(tabs) { tab in
                                TabBarButton(
                                    tab: tab,
                                    isActive: tab.id == activeTabID,
                                    isHovered: hoveredTabID == tab.id,
                                    onActivate: { onActivate(tab.id); onFocus() },
                                    onClose: { onClose(tab.id) }
                                )
                                .frame(width: tabWidth)
                                .onHover { hovering in
                                    hoveredTabID = hovering ? tab.id : nil
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .frame(minWidth: geometry.size.width)
                    }
                }
                .frame(height: 32)
                .background(.thinMaterial)
            }

            Rectangle()
                .fill(.separator)
                .frame(height: 1)
        }
    }
}

private struct TabBarButton: View {
    let tab: EditorPaneStateManager.EditorTab
    let isActive: Bool
    let isHovered: Bool
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var closeHovered = false

    private var displayName: String {
        URL(fileURLWithPath: tab.filePath).lastPathComponent
            + (tab.isDirty ? " \u{2022}" : "")
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity((closeHovered || isHovered || isActive) ? 1 : 0)
            .frame(width: 16, height: 16)
            .onHover { hovering in
                closeHovered = hovering
            }

            Text(displayName)
                .lineLimit(1)
                .font(.system(size: 11))
                .foregroundColor(isActive ? .primary : .secondary)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background {
            if isActive {
                Capsule()
                    .fill(.regularMaterial)
                    .glassEffect(.regular, in: Capsule())
            } else {
                Capsule()
                    .fill(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.25) : .clear)
                    .overlay(
                        Capsule()
                            .stroke(.separator.opacity(isHovered ? 0.25 : 0.1), lineWidth: 0.5)
                    )
            }
        }
        .contentShape(Capsule())
        .onTapGesture { onActivate() }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .overlay(MiddleClickView(action: onClose))
    }
}

private struct MiddleClickView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MiddleClickNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MiddleClickNSView)?.action = action
    }
}

private class MiddleClickNSView: NSView {
    var action: (() -> Void)?

    override func otherMouseDown(with event: NSEvent) {
        action?()
    }
}
