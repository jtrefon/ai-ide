import SwiftUI
import UniformTypeIdentifiers

struct EditorTabBar: View {
    let tabs: [EditorPaneStateManager.EditorTab]
    let activeTabID: UUID?
    let onActivate: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onFocus: () -> Void

    @State private var hoveredTabID: UUID?

    private let spacing: CGFloat = 8

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
                .frame(height: 34)
                .background(.thinMaterial)
            } else {
                HStack(spacing: spacing) {
                    ForEach(tabs) { tab in
                        TabBarButton(
                            tab: tab,
                            isActive: tab.id == activeTabID,
                            isHovered: hoveredTabID == tab.id,
                            onActivate: { onActivate(tab.id); onFocus() },
                            onClose: { onClose(tab.id) }
                        )
                        .frame(minWidth: 80)
                        .frame(maxWidth: .infinity)
                        .onHover { hovering in
                            hoveredTabID = hovering ? tab.id : nil
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .frame(height: 34)
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

    private var displayName: String {
        URL(fileURLWithPath: tab.filePath).lastPathComponent
    }

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 5) {
                Spacer(minLength: 4)

                FileTabIcon(filePath: tab.filePath)
                    .frame(width: 14, height: 14)

                Text(displayName)
                    .lineLimit(1)
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .primary : .secondary)

                if tab.isDirty {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isActive {
                    Capsule()
                        .glassEffect(.regular, in: Capsule())
                } else {
                    Capsule()
                        .fill(isHovered
                            ? Color(nsColor: .windowBackgroundColor).opacity(0.5)
                            : Color(nsColor: .windowBackgroundColor).opacity(0.35))
                        .overlay(
                            Capsule()
                                .stroke(Color(nsColor: .separatorColor).opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity((isHovered || isActive) ? 1 : 0)
            .frame(width: 24, height: 24)
            .padding(.leading, 4)
        }
        .overlay(MiddleClickView(action: onClose))
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

private struct FileTabIcon: View {
    let filePath: String

    var body: some View {
        let ext = URL(fileURLWithPath: filePath).pathExtension
        let image: NSImage? = ext.isEmpty ? nil : {
            if let utType = UTType(filenameExtension: ext) {
                return NSWorkspace.shared.icon(for: utType)
            }
            return nil
        }()

        if let image {
            Image(nsImage: image)
                .resizable()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "doc")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApplication.shared.currentEvent else { return nil }
        if event.type == .otherMouseDown || event.type == .otherMouseUp {
            return event.buttonNumber == 2 ? self : nil
        }
        return nil
    }
}
