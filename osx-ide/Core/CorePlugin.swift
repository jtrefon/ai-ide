//
//  CorePlugin.swift
//  osx-ide
//
//  Created by Jack Trefon on 21/12/2025.
//

import SwiftUI
import AppKit

/// The "Default Plugin" that registers the core UI components of the IDE.
/// In the future, these components could be fully separated into their own modules.
@MainActor
final class CorePlugin {
    static func initialize<Context: IDEContext & ObservableObject>(registry: UIRegistry, context: Context) {

        touchDiagnosticsStore(context: context)

        registerSidebarComponents(registry: registry, context: context)
        registerBottomPanelComponents(registry: registry, context: context)
        registerRightPanelComponents(registry: registry, context: context)

        registerStandardCommands(context: context)

        print("[CorePlugin] Initialized core UI components and commands")
    }

    private static func touchDiagnosticsStore<Context: IDEContext & ObservableObject>(context: Context) {
        _ = context.diagnosticsStore
    }

    private static func registerSidebarComponents<Context: IDEContext & ObservableObject>(registry: UIRegistry, context: Context) {
        registry.register(
            point: .sidebarLeft,
            name: "Internal.FileExplorer",
            icon: "folder",
            view: FileExplorerView(context: context)
        )
    }

    private static func registerBottomPanelComponents<Context: IDEContext & ObservableObject>(registry: UIRegistry, context: Context) {
        registry.register(
            point: .panelBottom,
            name: AppConstants.UI.internalTerminalPanelName,
            icon: "terminal",
            view: NativeTerminalView(
                currentDirectory: Binding(
                    get: { context.workspace.currentDirectory },
                    set: { _ in }
                ),
                ui: context.ui,
                eventBus: context.eventBus
            )
        )

        registry.register(
            point: .panelBottom,
            name: "Internal.Logs",
            icon: "doc.text.magnifyingglass",
            view: LogsPanelView(ui: context.ui, projectRoot: context.workspace.currentDirectory, eventBus: context.eventBus)
        )

        registry.register(
            point: .panelBottom,
            name: "Internal.Problems",
            icon: "exclamationmark.triangle",
            view: ProblemsView(store: context.diagnosticsStore, context: context)
        )
    }

    private static func registerRightPanelComponents<Context: IDEContext & ObservableObject>(registry: UIRegistry, context: Context) {
        registry.register(
            point: .panelRight,
            name: "Internal.AIChat",
            icon: "sparkles",
            view: AIChatPanel(
                selectionContext: context.selectionContext,
                conversationManager: context.conversationManager,
                ui: context.ui
            )
        )
    }

    private static func registerStandardCommands<Context: IDEContext & ObservableObject>(context: Context) {
        let commandRegistry = context.commandRegistry

        registerFileCommands(commandRegistry: commandRegistry, context: context)
        registerEditorCommands(commandRegistry: commandRegistry, context: context)
        registerViewCommands(commandRegistry: commandRegistry, context: context)
        registerWorkbenchCommands(commandRegistry: commandRegistry, context: context)
        registerExplorerCommands(commandRegistry: commandRegistry, context: context)
    }

    private static func registerFileCommands<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .fileNew) { _ in
            context.fileEditor.newFile()
        }

        commandRegistry.register(command: .projectNew) { _ in
            context.newProject()
        }

        commandRegistry.register(command: .fileOpen) { _ in
            context.openFile()
        }

        commandRegistry.register(command: .fileOpenFolder) { _ in
            Task { await context.workspace.openFolder() }
        }

        commandRegistry.register(command: .fileSave) { _ in
            context.fileEditor.saveFile()
        }

        commandRegistry.register(command: .fileSaveAs) { _ in
            Task { await context.fileEditor.saveFileAs() }
        }
    }

    private static func registerEditorCommands<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .editorFormat) { _ in
            let content = context.fileEditor.editorContent
            let languageStr = context.fileEditor.editorLanguage
            let language = CodeLanguage(rawValue: languageStr) ?? .unknown
            if let module = LanguageModuleManager.shared.getModule(for: language) {
                let formatted = module.format(content)
                context.fileEditor.editorContent = formatted
                return
            }

            context.fileEditor.editorContent = CodeFormatter.format(content, language: language)
        }

        registerNavigationCommands(commandRegistry: commandRegistry, context: context)
        registerEditorStateCommands(commandRegistry: commandRegistry, context: context)
        registerTextFinderCommands(commandRegistry: commandRegistry)
        registerMultiCursorCommands(commandRegistry: commandRegistry)
        registerInlineAIAssistCommand(commandRegistry: commandRegistry, context: context)
    }

    private static func registerNavigationCommands<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        registerGoToDefinitionCommand(commandRegistry: commandRegistry, context: context)
        registerFindReferencesCommand(commandRegistry: commandRegistry, context: context)
        registerRenameSymbolCommand(commandRegistry: commandRegistry, context: context)
    }

    private static func registerGoToDefinitionCommand<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .editorGoToDefinition) { _ in
            guard let root = context.workspace.currentDirectory?.standardizedFileURL else { return }

            guard let identifier = resolveWorkspaceIdentifier(context: context) else {
                context.lastError = "No symbol selected"
                return
            }

            let content = context.fileEditor.editorContent

            Task { @MainActor in
                let svc = WorkspaceNavigationService(codebaseIndexProvider: { context.codebaseIndex })
                let locations = await svc.findDefinitionLocations(
                    identifier: identifier,
                    projectRoot: root,
                    currentFilePath: context.fileEditor.selectedFile,
                    currentContent: content,
                    currentLanguage: context.fileEditor.editorLanguage,
                    limit: 50
                )

                if locations.isEmpty {
                    context.lastError = "No definition found for \"\(identifier)\"."
                    return
                }

                if locations.count == 1, let only = locations.first {
                    openWorkspaceLocation(only, projectRoot: root, context: context)
                    return
                }

                context.navigationLocationsTitle = "Definitions for \"\(identifier)\""
                context.navigationLocations = locations
                context.isNavigationLocationsPresented = true
                context.isQuickOpenPresented = false
                context.isGlobalSearchPresented = false
                context.isCommandPalettePresented = false
                context.isGoToSymbolPresented = false
                context.isRenameSymbolPresented = false
            }
        }
    }

    private static func registerFindReferencesCommand<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .editorFindReferences) { _ in
            guard let root = context.workspace.currentDirectory?.standardizedFileURL else { return }

            guard let identifier = resolveWorkspaceIdentifier(context: context) else {
                context.lastError = "No symbol selected"
                return
            }

            let svc = WorkspaceNavigationService(codebaseIndexProvider: { context.codebaseIndex })
            let locations = await svc.findReferenceLocations(identifier: identifier, projectRoot: root, limit: 500)

            if locations.isEmpty {
                context.lastError = "No references found for \"\(identifier)\"."
                return
            }

            context.navigationLocationsTitle = "References for \"\(identifier)\""
            context.navigationLocations = locations
            context.isNavigationLocationsPresented = true
            context.isQuickOpenPresented = false
            context.isGlobalSearchPresented = false
            context.isCommandPalettePresented = false
            context.isGoToSymbolPresented = false
            context.isRenameSymbolPresented = false
        }
    }

    private static func registerRenameSymbolCommand<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .editorRenameSymbol) { _ in
            guard let identifier = resolveWorkspaceIdentifier(context: context) else {
                context.lastError = "No symbol selected"
                return
            }

            context.renameSymbolIdentifier = identifier
            context.isRenameSymbolPresented = true
            context.isNavigationLocationsPresented = false
            context.isQuickOpenPresented = false
            context.isGlobalSearchPresented = false
            context.isCommandPalettePresented = false
            context.isGoToSymbolPresented = false
        }
    }

    private static func registerEditorStateCommands<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .editorTabsCloseActive) { _ in
            context.fileEditor.closeActiveTab()
        }

        commandRegistry.register(command: .editorTabsCloseAll) { _ in
            context.fileEditor.closeAllTabs()
        }

        commandRegistry.register(command: .editorTabsNext) { _ in
            context.fileEditor.activateNextTab()
        }

        commandRegistry.register(command: .editorTabsPrevious) { _ in
            context.fileEditor.activatePreviousTab()
        }

        commandRegistry.register(command: .editorSplitRight) { _ in
            context.fileEditor.toggleSplit(axis: .vertical)
        }

        commandRegistry.register(command: .editorSplitDown) { _ in
            context.fileEditor.toggleSplit(axis: .horizontal)
        }

        commandRegistry.register(command: .editorFocusNextGroup) { _ in
            context.fileEditor.focusNextPane()
        }
    }

    private static func registerTextFinderCommands(commandRegistry: CommandRegistry) {
        commandRegistry.register(command: .editorFind) { _ in
            let item = NSMenuItem()
            item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
            NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
        }

        commandRegistry.register(command: .editorReplace) { _ in
            let item = NSMenuItem()
            item.tag = Int(NSTextFinder.Action.showReplaceInterface.rawValue)
            NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
        }

        commandRegistry.register(command: .editorToggleFold) { _ in
            NSApp.sendAction(#selector(CodeEditorTextView.toggleFoldAtCursor(_:)), to: nil, from: nil)
        }

        commandRegistry.register(command: .editorUnfoldAll) { _ in
            NSApp.sendAction(#selector(CodeEditorTextView.unfoldAll(_:)), to: nil, from: nil)
        }
    }

    private static func registerMultiCursorCommands(commandRegistry: CommandRegistry) {
        commandRegistry.register(command: .editorAddNextOccurrence) { _ in
            NSApp.sendAction(#selector(CodeEditorTextView.addNextOccurrence(_:)), to: nil, from: nil)
        }

        commandRegistry.register(command: .editorAddCursorAbove) { _ in
            NSApp.sendAction(#selector(CodeEditorTextView.addCursorAbove(_:)), to: nil, from: nil)
        }

        commandRegistry.register(command: .editorAddCursorBelow) { _ in
            NSApp.sendAction(#selector(CodeEditorTextView.addCursorBelow(_:)), to: nil, from: nil)
        }
    }

    private static func registerInlineAIAssistCommand<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .editorAIInlineAssist) { _ in
            context.ui.isAIChatVisible = true

            let pane = context.fileEditor.focusedPaneState
            let selectionContext = EditorAIContextBuilder.build(
                filePath: pane.selectedFile,
                language: pane.editorLanguage,
                buffer: pane.editorContent,
                selection: pane.selectedRange
            )

            let userPrompt = "Analyze this code and suggest improvements. If there are any obvious bugs, point them out and propose fixes."
            context.conversationManager.currentInput = userPrompt
            context.conversationManager.sendMessage(context: selectionContext)
        }
    }

    private static func registerViewCommands<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .viewToggleMinimap) { _ in
            context.ui.toggleMinimap()
        }

        commandRegistry.register(command: .searchFindInWorkspace) { _ in
            context.isGlobalSearchPresented = true
            context.isQuickOpenPresented = false
        }

        commandRegistry.register(command: .viewToggleProblems) { _ in
            context.ui.isTerminalVisible = true
            context.ui.bottomPanelSelectedName = "Internal.Problems"
        }

        commandRegistry.register(command: .problemsNext) { _ in
            context.ui.isTerminalVisible = true
            context.ui.bottomPanelSelectedName = "Internal.Problems"
            if let d = context.diagnosticsStore.selectNext() {
                openDiagnostic(d, context: context)
            }
        }

        commandRegistry.register(command: .problemsPrevious) { _ in
            context.ui.isTerminalVisible = true
            context.ui.bottomPanelSelectedName = "Internal.Problems"
            if let d = context.diagnosticsStore.selectPrevious() {
                openDiagnostic(d, context: context)
            }
        }
    }

    private static func registerWorkbenchCommands<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .workbenchQuickOpen) { _ in
            context.isQuickOpenPresented = true
            context.isGlobalSearchPresented = false
            context.isCommandPalettePresented = false
            context.isGoToSymbolPresented = false
        }

        commandRegistry.register(command: .workbenchCommandPalette) { _ in
            context.isCommandPalettePresented = true
            context.isQuickOpenPresented = false
            context.isGlobalSearchPresented = false
            context.isGoToSymbolPresented = false
        }

        commandRegistry.register(command: .workbenchGoToSymbol) { _ in
            context.isGoToSymbolPresented = true
            context.isQuickOpenPresented = false
            context.isGlobalSearchPresented = false
            context.isCommandPalettePresented = false
        }
    }

    private static func registerExplorerCommands<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        registerExplorerOpenSelectionCommand(commandRegistry: commandRegistry, context: context)
        registerExplorerDeleteSelectionCommand(commandRegistry: commandRegistry, context: context)
        registerExplorerRenameSelectionCommand(commandRegistry: commandRegistry, context: context)
        registerExplorerRevealInFinderCommand(commandRegistry: commandRegistry, context: context)
    }

    private static func registerExplorerOpenSelectionCommand<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .explorerOpenSelection) { (args: ExplorerPathArgs) in
            let path = args.path
            guard let root = context.workspace.currentDirectory?.standardizedFileURL else { return }
            do {
                let url = try context.workspaceService.makePathValidator(projectRoot: root).validateAndResolve(path)
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDirectory {
                    context.loadFile(from: url)
                }
            } catch {
                context.lastError = error.localizedDescription
            }
        }
    }

    private static func registerExplorerDeleteSelectionCommand<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .explorerDeleteSelection) { (args: ExplorerPathArgs) in
            let path = args.path
            guard let root = context.workspace.currentDirectory?.standardizedFileURL else { return }
            do {
                let url = try context.workspaceService.makePathValidator(projectRoot: root).validateAndResolve(path)
                context.workspaceService.deleteItem(at: url)

                context.fileEditor.closeTab(filePath: url.path)
                context.workspace.removeOpenFile(url)
            } catch {
                context.lastError = error.localizedDescription
            }
        }
    }

    private static func registerExplorerRenameSelectionCommand<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .explorerRenameSelection) { (args: ExplorerRenameArgs) in
            let path = args.path
            let newName = args.newName
            guard let root = context.workspace.currentDirectory?.standardizedFileURL else { return }
            do {
                let url = try context.workspaceService.makePathValidator(projectRoot: root).validateAndResolve(path)

                if context.fileEditor.isFileOpenAndDirty(filePath: url.path) {
                    context.lastError = "Save changes before renaming an open file."
                    return
                }

                guard let newURL = context.workspaceService.renameItem(at: url, to: newName) else { return }

                context.fileEditor.renameTab(oldPath: url.path, newPath: newURL.path)

                context.workspace.removeOpenFile(url)
                context.workspace.addOpenFile(newURL)
            } catch {
                context.lastError = error.localizedDescription
            }
        }
    }

    private static func registerExplorerRevealInFinderCommand<Context: IDEContext & ObservableObject>(commandRegistry: CommandRegistry, context: Context) {
        commandRegistry.register(command: .explorerRevealInFinder) { (args: ExplorerPathArgs) in
            let path = args.path
            guard let root = context.workspace.currentDirectory?.standardizedFileURL else { return }
            do {
                let url = try context.workspaceService.makePathValidator(projectRoot: root).validateAndResolve(path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                context.lastError = error.localizedDescription
            }
        }
    }

    private static func resolveWorkspaceIdentifier<Context: IDEContext & ObservableObject>(context: Context) -> String? {
        let selected = context.selectionContext.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if WorkspaceNavigationService.isValidIdentifier(selected) {
            return selected
        }

        let content = context.fileEditor.editorContent
        let cursor = context.fileEditor.selectedRange?.location ?? 0
        return WorkspaceNavigationService.identifierAtCursor(in: content, cursor: cursor)
    }

    @MainActor
    private static func openWorkspaceLocation<Context: IDEContext & ObservableObject>(
        _ loc: WorkspaceCodeLocation,
        projectRoot: URL,
        context: Context
    ) {
        do {
            let url = try context.workspaceService.makePathValidator(projectRoot: projectRoot).validateAndResolve(loc.relativePath)
            context.loadFile(from: url)
            context.fileEditor.selectLine(loc.line)
        } catch {
            context.lastError = error.localizedDescription
        }
    }

    @MainActor
    private static func openDiagnostic<Context: IDEContext & ObservableObject>(_ d: Diagnostic, context: Context) {
        let url: URL

        if d.relativePath.hasPrefix("/") {
            url = URL(fileURLWithPath: d.relativePath)
        } else if let root = context.workspace.currentDirectory?.standardizedFileURL {
            do {
                url = try context.workspaceService.makePathValidator(projectRoot: root).validateAndResolve(d.relativePath)
            } catch {
                context.lastError = error.localizedDescription
                return
            }
        } else {
            context.lastError = "No workspace open."
            return
        }

        context.loadFile(from: url)
        context.fileEditor.selectLine(d.line)
    }
}
