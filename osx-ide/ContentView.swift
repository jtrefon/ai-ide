//
//  ContentView.swift
//  osx-ide
//
//  Created by Jack Trefon on 25/08/2025.
//

import SwiftUI
import AppKit

private enum HorizontalPanelKind: Hashable {
    case sidebar
    case chat
}

private struct HorizontalPanelWidthPreferenceKey: PreferenceKey {
    static let defaultValue: [HorizontalPanelKind: CGFloat] = [:]

    static func reduce(value: inout [HorizontalPanelKind: CGFloat], nextValue: () -> [HorizontalPanelKind: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ContentView: View {
    let appState: AppState
    @ObservedObject private var fileEditor: FileEditorStateManager
    @ObservedObject private var workspace: WorkspaceStateManager
    @ObservedObject private var uiState: UIStateManager
    @ObservedObject private var registry: UIRegistry

    @State private var logsFollow: Bool = true
    @State private var logsSource: String = LogsPanelView.LogSource.app.rawValue

    init(appState: AppState) {
        self.appState = appState
        self._fileEditor = ObservedObject(wrappedValue: appState.fileEditor)
        self._workspace = ObservedObject(wrappedValue: appState.workspace)
        self._uiState = ObservedObject(wrappedValue: appState.ui)
        self._registry = ObservedObject(wrappedValue: appState.uiRegistry)
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        let _ = trackViewRender("ContentView.body")
        return rootView
    }

    private var rootView: some View {
        let _ = trackViewRender("ContentView.rootView")
        return ZStack {
            mainLayout
            OverlayHostView(appState: appState)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .environment(\.font, .system(size: CGFloat(uiState.fontSize)))
        .preferredColorScheme(appState.selectedTheme.colorScheme)
        .accessibilityIdentifier(AccessibilityID.appRootView)
        .accessibilityValue("theme=\(appState.selectedTheme.rawValue)")
    }

    private var mainLayout: some View {
        let _ = trackViewRender("ContentView.mainLayout")
        return VStack(spacing: 0) {
            WindowSetupView(appState: appState)
            workspaceLayout
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IndexStatusBarView(
                appState: appState,
                codebaseIndexProvider: { appState.codebaseIndex },
                eventBus: appState.eventBus
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workspaceLayout: some View {
        let _ = trackViewRender("ContentView.workspaceLayout")
        return HSplitView {
            if uiState.isSidebarVisible, let pluginView = registry.views(for: .sidebarLeft).first {
                pluginView.makeView()
                    .frame(
                        minWidth: AppConstants.Layout.minSidebarWidth,
                        idealWidth: uiState.sidebarWidth,
                        maxWidth: AppConstants.Layout.maxSidebarWidth
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HorizontalPanelWidthPreferenceKey.self,
                                value: [.sidebar: proxy.size.width]
                            )
                        }
                    )
                    .accessibilityIdentifier(AccessibilityID.leftSidebarPanel)
            }

            HSplitView {
                editorAndTerminal

                if uiState.isAIChatVisible, let pluginView = registry.views(for: .panelRight).first {
                    pluginView.makeView()
                        .frame(
                            minWidth: AppConstants.Layout.minChatPanelWidth,
                            idealWidth: uiState.chatPanelWidth,
                            maxWidth: AppConstants.Layout.maxChatPanelWidth
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: HorizontalPanelWidthPreferenceKey.self,
                                    value: [.chat: proxy.size.width]
                                )
                            }
                        )
                        .accessibilityIdentifier(AccessibilityID.rightChatPanel)
                }
            }
        }
        .onPreferenceChange(HorizontalPanelWidthPreferenceKey.self) { widths in
            if let sidebar = widths[.sidebar], uiState.isSidebarVisible, abs(uiState.sidebarWidth - sidebar) > 1 {
                uiState.updateSidebarWidth(sidebar)
            }
            if let chat = widths[.chat], uiState.isAIChatVisible, abs(uiState.chatPanelWidth - chat) > 1 {
                uiState.updateChatPanelWidth(chat)
            }
        }
    }

    private var editorAndTerminal: some View {
        EditorTerminalSplitView(
            isTerminalVisible: uiState.isTerminalVisible,
            terminalHeight: uiState.terminalHeight,
            setTerminalHeight: { uiState.updateTerminalHeight($0) },
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
                showLineNumbers: uiState.showLineNumbers,
                wordWrap: uiState.wordWrap,
                minimapVisible: uiState.minimapVisible,
                fontSize: uiState.fontSize,
                fontFamily: uiState.fontFamily
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
            showLineNumbers: uiState.showLineNumbers,
            wordWrap: uiState.wordWrap,
            minimapVisible: uiState.minimapVisible,
            fontSize: uiState.fontSize,
            fontFamily: uiState.fontFamily
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
            let selectedName = uiState.bottomPanelSelectedName
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

            Picker(localized("bottom_panel.picker"), selection: $uiState.bottomPanelSelectedName) {
                ForEach(bottomViews) { view in
                    Text(view.name.replacingOccurrences(of: "Internal.", with: ""))
                        .tag(view.name)
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
            Button(
                action: {
                    appState.eventBus.publish(TerminalClearRequestedEvent())
                },
                label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            )
            .buttonStyle(.borderless)
            .help(localized("terminal.clear_help"))

            Text(localized("bottom_panel.terminal"))
                .font(.system(size: max(10, uiState.fontSize - 2), weight: .medium))
        } else if selectedName == "Internal.Logs" {
            Text(localized("bottom_panel.logs"))
                .font(.system(size: max(10, uiState.fontSize - 2), weight: .medium))
        } else if selectedName == "Internal.Problems" {
            Text(localized("bottom_panel.problems"))
                .font(.system(size: max(10, uiState.fontSize - 2), weight: .medium))
        }
    }

    @ViewBuilder
    private func bottomPanelTrailingControls(selectedName: String) -> some View {
        if selectedName == AppConstants.UI.internalTerminalPanelName {
            Text(workspace.currentDirectory?.lastPathComponent ?? localized("bottom_panel.terminal"))
                .font(.system(size: max(10, uiState.fontSize - 3)))
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else if selectedName == "Internal.Logs" {
            Toggle(localized("logs.follow"), isOn: $logsFollow)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: logsFollow) { _, newValue in
                    appState.eventBus.publish(LogsFollowChangedEvent(follow: newValue))
                }

            Picker(localized("logs.source"), selection: $logsSource) {
                ForEach(LogsPanelView.LogSource.allCases) { src in
                    Text(src.title).tag(src.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: logsSource) { _, newValue in
                appState.eventBus.publish(LogsSourceChangedEvent(sourceRawValue: newValue))
            }

            Button(localized("common.clear")) {
                appState.eventBus.publish(LogsClearRequestedEvent())
            }
            .buttonStyle(.borderless)
        } else if selectedName == "Internal.Problems" {
            Button(localized("common.clear")) {
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
                                    let clamped = max(
                                        AppConstants.Layout.minTerminalHeight,
                                        min(maxAllowedTerminal, proposed)
                                    )
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

private struct WindowSetupView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        WindowAccessor { window in
            appState.windowProvider.setWindow(window)
            appState.attachWindow(window)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = false
            window.isMovableByWindowBackground = false
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor
            window.hasShadow = true
            window.styleMask.insert(.resizable)
            window.styleMask.insert(.unifiedTitleAndToolbar)
            window.minSize = NSSize(width: 900, height: 600)
            
            // Normalize persisted geometry against the currently visible frame.
            if let screen = window.screen ?? NSScreen.main {
                let normalized = UILayoutNormalizer.normalizeWindowFrame(
                    window.frame,
                    screenVisibleFrame: screen.visibleFrame
                )
                if normalized != window.frame {
                    window.setFrame(normalized, display: true)
                }
            }
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
                onDismiss: { appState.isGlobalSearchPresented = false },
                content: {
                    GlobalSearchOverlayView(appState: appState, isPresented: $appState.isGlobalSearchPresented)
                }
            )

            OverlayContainer(
                isPresented: $appState.isQuickOpenPresented,
                onDismiss: { appState.isQuickOpenPresented = false },
                content: {
                    QuickOpenOverlayView(appState: appState, isPresented: $appState.isQuickOpenPresented)
                }
            )

            OverlayContainer(
                isPresented: $appState.isCommandPalettePresented,
                onDismiss: { appState.isCommandPalettePresented = false },
                content: {
                    CommandPaletteOverlayView(
                        commandRegistry: appState.commandRegistry,
                        isPresented: $appState.isCommandPalettePresented
                    )
                }
            )

            OverlayContainer(
                isPresented: $appState.isGoToSymbolPresented,
                onDismiss: { appState.isGoToSymbolPresented = false },
                content: {
                    GoToSymbolOverlayView(appState: appState, isPresented: $appState.isGoToSymbolPresented)
                }
            )

            OverlayContainer(
                isPresented: $appState.isNavigationLocationsPresented,
                onDismiss: { appState.isNavigationLocationsPresented = false },
                content: {
                    NavigationLocationsOverlayView(
                        appState: appState,
                        isPresented: $appState.isNavigationLocationsPresented
                    )
                }
            )

            OverlayContainer(
                isPresented: $appState.isRenameSymbolPresented,
                onDismiss: { appState.isRenameSymbolPresented = false },
                content: {
                    RenameSymbolOverlayView(appState: appState, isPresented: $appState.isRenameSymbolPresented)
                }
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(appState: DependencyContainer().makeAppState())
    }
}
