//
//  LayoutCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import SwiftUI
import AppKit

/// Manages the main application layout and panel resizing
@MainActor
struct LayoutCoordinator {
    
    // MARK: - Properties
    
    let ui: UIStateManager

    // MARK: - Initialization
    
    // MARK: - Public Methods
    
    /// Creates the main application layout
	func makeMainLayout<Sidebar: View, Editor: View, RightPanel: View, Terminal: View>(
		sidebar: Sidebar,
		editor: Editor,
		rightPanel: RightPanel,
		terminal: Terminal
	) -> some View {
		LayoutView(
			ui: ui,
			sidebar: AnyView(sidebar),
			editor: AnyView(editor),
			rightPanel: AnyView(rightPanel),
			terminal: AnyView(terminal)
		)
	}
}

private struct LayoutView: View {
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
								let clamped = max(AppConstants.Layout.minTerminalHeight, min(maxAllowedTerminal, proposed))
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

// MARK: - Supporting Views

private struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        CursorRectNSView(cursor: .resizeUpDown)
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class CursorRectNSView: NSView {
    let cursor: NSCursor
    
    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }
}
