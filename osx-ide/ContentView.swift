//
//  ContentView.swift
//  osx-ide
//
//  Created by Jack Trefon on 25/08/2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    let appState: AppState
    @ObservedObject private var fileEditor: FileEditorStateManager
    @ObservedObject private var workspace: WorkspaceStateManager
    @ObservedObject private var ui: UIStateManager
    @ObservedObject private var registry: UIRegistry

    @State private var logsFollow: Bool = true
    @State private var logsSource: String = LogsPanelView.LogSource.app.rawValue

    init(appState: AppState) {
        self.appState = appState
        self._fileEditor = ObservedObject(wrappedValue: appState.fileEditor)
        self._workspace = ObservedObject(wrappedValue: appState.workspace)
        self._ui = ObservedObject(wrappedValue: appState.ui)
        self._registry = ObservedObject(wrappedValue: appState.uiRegistry)
    }

    private struct EditorPaneView: View {
        @ObservedObject var pane: EditorPaneStateManager
        let isFocused: Bool
        let onFocus: () -> Void
        let selectionContext: CodeSelectionContext
        let showLineNumbers: Bool
        let wordWrap: Bool
        let minimapVisible: Bool
        let fontSize: Double
        let fontFamily: String

        var body: some View {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if pane.tabs.isEmpty {
                            Text("Untitled")
                                .font(.headline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(pane.tabs) { tab in
                                let isActive = tab.id == pane.activeTabID
                                Button(action: {
                                    onFocus()
                                    pane.activateTab(id: tab.id)
                                }) {
                                    HStack(spacing: 6) {
                                        Text(URL(fileURLWithPath: tab.filePath).lastPathComponent + (tab.isDirty ? " •" : ""))
                                            .lineLimit(1)

                                        Button(action: {
                                            onFocus()
                                            pane.closeTab(id: tab.id)
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isActive ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .frame(height: 34)
                .background(Color(NSColor.windowBackgroundColor))

                HStack(spacing: 0) {
                    CodeEditorView(
                        text: $pane.editorContent,
                        language: pane.editorLanguage,
                        selectedRange: $pane.selectedRange,
                        selectionContext: selectionContext,
                        showLineNumbers: showLineNumbers,
                        wordWrap: wordWrap,
                        fontSize: fontSize,
                        fontFamily: fontFamily
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        Rectangle()
                            .stroke(isFocused ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 2)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onFocus()
                    }

                    if minimapVisible {
                        Divider()
                        MinimapView(
                            text: $pane.editorContent,
                            selectedRange: $pane.selectedRange,
                            fontFamily: fontFamily
                        )
                    }
                }
            }
        }
    }
    
    var body: some View {
        rootView
    }

    private var rootView: some View {
        ZStack {
            mainLayout
            OverlayHostView(appState: appState)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .environment(\.font, .system(size: CGFloat(ui.fontSize)))
        .preferredColorScheme(appState.selectedTheme.colorScheme)
        .accessibilityIdentifier("AppRootView")
        .accessibilityValue("theme=\(appState.selectedTheme.rawValue)")
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            WindowSetupView(appState: appState)
            workspaceLayout
            IndexStatusBarView(appState: appState, codebaseIndexProvider: { appState.codebaseIndex }, eventBus: appState.eventBus)
        }
    }

    private var workspaceLayout: some View {
        HSplitView {
            if ui.isSidebarVisible, let pluginView = registry.views(for: .sidebarLeft).first {
                pluginView.makeView().frame(minWidth: 200, maxWidth: 300)
            }

            HSplitView {
                editorAndTerminal

                if ui.isAIChatVisible, let pluginView = registry.views(for: .panelRight).first {
                    pluginView.makeView().frame(minWidth: 240, maxWidth: 340)
                }
            }
        }
    }

    private var editorAndTerminal: some View {
        EditorTerminalSplitView(
            isTerminalVisible: ui.isTerminalVisible,
            terminalHeight: ui.terminalHeight,
            setTerminalHeight: { ui.updateTerminalHeight($0) },
            editor: { editorArea },
            terminal: { terminalPanel }
        )
        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var editorArea: some View {
        if fileEditor.isSplitEditor {
            if fileEditor.splitAxis == .vertical {
                HSplitView {
                    editorPane(.primary)
                    editorPane(.secondary)
                }
            } else {
                VSplitView {
                    editorPane(.primary)
                    editorPane(.secondary)
                }
            }
        } else {
            EditorPaneView(
                pane: fileEditor.primaryPane,
                isFocused: true,
                onFocus: { fileEditor.focus(.primary) },
                selectionContext: appState.selectionContext,
                showLineNumbers: ui.showLineNumbers,
                wordWrap: ui.wordWrap,
                minimapVisible: ui.minimapVisible,
                fontSize: ui.fontSize,
                fontFamily: ui.fontFamily
            )
        }
    }

    private func editorPane(_ pane: FileEditorStateManager.PaneID) -> some View {
        let manager = (pane == .primary) ? fileEditor.primaryPane : fileEditor.secondaryPane
        let focused = (pane == .primary) ? fileEditor.focusedPane == .primary : fileEditor.focusedPane == .secondary

        return EditorPaneView(
            pane: manager,
            isFocused: focused,
            onFocus: { fileEditor.focus(pane) },
            selectionContext: appState.selectionContext,
            showLineNumbers: ui.showLineNumbers,
            wordWrap: ui.wordWrap,
            minimapVisible: ui.minimapVisible,
            fontSize: ui.fontSize,
            fontFamily: ui.fontFamily
        )
    }

    @ViewBuilder
    private var terminalPanel: some View {
        let bottomViews = registry.views(for: .panelBottom)

        if bottomViews.count == 1, let pluginView = bottomViews.first {
            pluginView.makeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .frame(minHeight: 100)
        } else if bottomViews.count > 1 {
            let selectedName = ui.bottomPanelSelectedName
            let selectedView = bottomViews.first(where: { $0.name == selectedName }) ?? bottomViews[0]

            VStack(spacing: 0) {
                bottomPanelHeader(selectedName: selectedName, bottomViews: bottomViews)
                selectedView.makeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .frame(minHeight: 100)
        }
    }

    private func bottomPanelHeader(selectedName: String, bottomViews: [PluginView]) -> some View {
        HStack(spacing: 8) {
            bottomPanelLeadingControls(selectedName: selectedName)

            Spacer(minLength: 0)

            Picker("Bottom Panel", selection: $ui.bottomPanelSelectedName) {
                ForEach(bottomViews) { v in
                    Text(v.name.replacingOccurrences(of: "Internal.", with: ""))
                        .tag(v.name)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            Spacer(minLength: 0)

            bottomPanelTrailingControls(selectedName: selectedName)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: AppConstants.Layout.headerHeight)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func bottomPanelLeadingControls(selectedName: String) -> some View {
        if selectedName == AppConstants.UI.internalTerminalPanelName {
            Button(action: {
                appState.eventBus.publish(TerminalClearRequestedEvent())
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Clear Terminal")

            Text("Terminal")
                .font(.system(size: max(10, ui.fontSize - 2), weight: .medium))
        } else if selectedName == "Internal.Logs" {
            Text("Logs")
                .font(.system(size: max(10, ui.fontSize - 2), weight: .medium))
        } else if selectedName == "Internal.Problems" {
            Text("Problems")
                .font(.system(size: max(10, ui.fontSize - 2), weight: .medium))
        }
    }

    @ViewBuilder
    private func bottomPanelTrailingControls(selectedName: String) -> some View {
        if selectedName == AppConstants.UI.internalTerminalPanelName {
            Text(workspace.currentDirectory?.lastPathComponent ?? "Terminal")
                .font(.system(size: max(10, ui.fontSize - 3)))
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else if selectedName == "Internal.Logs" {
            Toggle("Follow", isOn: $logsFollow)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: logsFollow) { _, newValue in
                    appState.eventBus.publish(LogsFollowChangedEvent(follow: newValue))
                }

            Picker("Source", selection: $logsSource) {
                ForEach(LogsPanelView.LogSource.allCases) { src in
                    Text(src.title).tag(src.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: logsSource) { _, newValue in
                appState.eventBus.publish(LogsSourceChangedEvent(sourceRawValue: newValue))
            }

            Button("Clear") {
                appState.eventBus.publish(LogsClearRequestedEvent())
            }
            .buttonStyle(.borderless)
        } else if selectedName == "Internal.Problems" {
            Button("Clear") {
                appState.eventBus.publish(ProblemsClearRequestedEvent())
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct EditorTerminalSplitView<Editor: View, Terminal: View>: View {
    let isTerminalVisible: Bool
    let terminalHeight: Double
    let setTerminalHeight: (Double) -> Void
    let editor: () -> Editor
    let terminal: () -> Terminal

    @State private var dragStartTerminalHeight: Double?

    private let dividerHeight: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let containerHeight = proxy.size.height
            let minEditorHeight = Double(AppConstants.Layout.minTerminalHeight)
            let maxAllowedTerminal = max(
                AppConstants.Layout.minTerminalHeight,
                min(AppConstants.Layout.maxTerminalHeight, containerHeight - minEditorHeight - Double(dividerHeight))
            )

            VStack(spacing: 0) {
                editor()
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
                                    setTerminalHeight(clamped)
                                }
                                .onEnded { _ in
                                    dragStartTerminalHeight = nil
                                }
                        )

                    terminal()
                        .frame(maxWidth: .infinity)
                        .frame(height: terminalHeight)
                }
            }
        }
    }
}

private struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        CursorRectNSView(cursor: .resizeUpDown)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class CursorRectNSView: NSView {
    private let cursor: NSCursor

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }
}

private struct WindowSetupView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        WindowAccessor { window in
            appState.windowProvider.setWindow(window)
            appState.attachWindow(window)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor
            window.hasShadow = true
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.insert(.unifiedTitleAndToolbar)
        }
        .frame(width: 0, height: 0)
    }
}

private struct OverlayHostView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            OverlayContainer(
                isPresented: $appState.isGlobalSearchPresented,
                onDismiss: { appState.isGlobalSearchPresented = false }
            ) {
                GlobalSearchOverlayView(appState: appState, isPresented: $appState.isGlobalSearchPresented)
            }

            OverlayContainer(
                isPresented: $appState.isQuickOpenPresented,
                onDismiss: { appState.isQuickOpenPresented = false }
            ) {
                QuickOpenOverlayView(appState: appState, isPresented: $appState.isQuickOpenPresented)
            }

            OverlayContainer(
                isPresented: $appState.isCommandPalettePresented,
                onDismiss: { appState.isCommandPalettePresented = false }
            ) {
                CommandPaletteOverlayView(commandRegistry: appState.commandRegistry, isPresented: $appState.isCommandPalettePresented)
            }

            OverlayContainer(
                isPresented: $appState.isGoToSymbolPresented,
                onDismiss: { appState.isGoToSymbolPresented = false }
            ) {
                GoToSymbolOverlayView(appState: appState, isPresented: $appState.isGoToSymbolPresented)
            }

            OverlayContainer(
                isPresented: $appState.isNavigationLocationsPresented,
                onDismiss: { appState.isNavigationLocationsPresented = false }
            ) {
                NavigationLocationsOverlayView(appState: appState, isPresented: $appState.isNavigationLocationsPresented)
            }

            OverlayContainer(
                isPresented: $appState.isRenameSymbolPresented,
                onDismiss: { appState.isRenameSymbolPresented = false }
            ) {
                RenameSymbolOverlayView(appState: appState, isPresented: $appState.isRenameSymbolPresented)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    ContentView(appState: DependencyContainer().makeAppState())
}
