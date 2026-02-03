import SwiftUI

struct LayoutView: View {
    @ObservedObject var ui: UIStateManager
    let sidebar: AnyView
    let editor: AnyView
    let rightPanel: AnyView
    let terminal: AnyView

    @State private var dragStartTerminalHeight: Double?

    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                sidebar

                VStack(spacing: 0) {
                    editorTerminalLayout(containerHeight: geometry.size.height)
                }
                .frame(minWidth: 0, maxWidth: .infinity)

                rightPanel
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func editorTerminalLayout(containerHeight: CGFloat) -> some View {
        let isTerminalVisible = ui.isTerminalVisible
        let terminalHeight = ui.terminalHeight
        let dividerHeight: CGFloat = 1

        let minEditorHeight = Double(AppConstants.Layout.minTerminalHeight)
        let maxAllowedTerminal = max(
            AppConstants.Layout.minTerminalHeight,
            min(AppConstants.Layout.maxTerminalHeight, containerHeight - minEditorHeight - Double(dividerHeight))
        )

        VStack(spacing: 0) {
            editor
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)

            if isTerminalVisible {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: dividerHeight)
                    .contentShape(Rectangle())
                    .overlay(
                        ResizeCursorView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartTerminalHeight == nil {
                                    dragStartTerminalHeight = terminalHeight
                                }

                                let start = dragStartTerminalHeight ?? terminalHeight
                                let proposed = start - value.translation.height
                                let clamped = max(
                                    AppConstants.Layout.minTerminalHeight,
                                    min(maxAllowedTerminal, proposed)
                                )
                                ui.terminalHeight = clamped
                            }
                            .onEnded { _ in
                                dragStartTerminalHeight = nil
                            }
                    )

                terminal
                    .frame(maxWidth: .infinity)
                    .frame(height: terminalHeight)
            }
        }
    }
}
