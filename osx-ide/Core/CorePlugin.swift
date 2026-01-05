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
    static func initialize(registry: UIRegistry, appState: AppState) {
        
        // Register File Explorer (Sidebar)
        registry.register(
            point: .sidebarLeft,
            name: "Internal.FileExplorer",
            icon: "folder",
            view: FileExplorerView(appState: appState)
        )
        
        // Register Terminal (Bottom Panel)
        registry.register(
            point: .panelBottom,
            name: "Internal.Terminal",
            icon: "terminal",
            view: NativeTerminalView(
                currentDirectory: Binding(
                    get: { appState.workspace.currentDirectory },
                    set: { _ in }
                ),
                ui: appState.ui
            )
        )
        
        // Register AI Chat (Right Panel)
        registry.register(
            point: .panelRight,
            name: "Internal.AIChat",
            icon: "sparkles",
            view: AIChatPanel(
                selectionContext: appState.selectionContext, // Use shared context
                conversationManager: appState.conversationManager,
                ui: appState.ui
            )
        )
        
        // Register Standard Commands
        let commandRegistry = CommandRegistry.shared
        
        commandRegistry.register(command: .fileNew) { _ in
            appState.fileEditor.newFile()
        }

        commandRegistry.register(command: .projectNew) { _ in
            appState.newProject()
        }

        commandRegistry.register(command: .fileOpen) { _ in
            appState.openFile()
        }
        
        commandRegistry.register(command: .fileOpenFolder) { _ in
            Task { await appState.workspace.openFolder() }
        }
        
        commandRegistry.register(command: .fileSave) { _ in
            appState.fileEditor.saveFile()
        }
        
        commandRegistry.register(command: .fileSaveAs) { _ in
            Task { await appState.fileEditor.saveFileAs() }
        }
        
        commandRegistry.register(command: .editorFormat) { _ in
            let content = appState.fileEditor.editorContent
            let languageStr = appState.fileEditor.editorLanguage
            let language = CodeLanguage(rawValue: languageStr) ?? .unknown
            if let module = await LanguageModuleManager.shared.getModule(for: language) {
                let formatted = module.format(content)
                appState.fileEditor.editorContent = formatted
                return
            }

            appState.fileEditor.editorContent = CodeFormatter.format(content, language: language)
        }

        commandRegistry.register(command: .editorTabsCloseActive) { _ in
            appState.fileEditor.closeActiveTab()
        }

        commandRegistry.register(command: .editorTabsCloseAll) { _ in
            appState.fileEditor.closeAllTabs()
        }

        commandRegistry.register(command: .editorTabsNext) { _ in
            appState.fileEditor.activateNextTab()
        }

        commandRegistry.register(command: .editorTabsPrevious) { _ in
            appState.fileEditor.activatePreviousTab()
        }

        commandRegistry.register(command: .editorSplitRight) { _ in
            appState.fileEditor.toggleSplit(axis: .vertical)
        }

        commandRegistry.register(command: .editorSplitDown) { _ in
            appState.fileEditor.toggleSplit(axis: .horizontal)
        }

        commandRegistry.register(command: .editorFocusNextGroup) { _ in
            appState.fileEditor.focusNextPane()
        }

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

        commandRegistry.register(command: .explorerOpenSelection) { args in
            guard let path = args["path"] as? String else { return }
            guard let root = appState.workspace.currentDirectory?.standardizedFileURL else { return }
            do {
                let url = try PathValidator(projectRoot: root).validateAndResolve(path)
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDirectory {
                    appState.loadFile(from: url)
                }
            } catch {
                appState.lastError = error.localizedDescription
            }
        }

        commandRegistry.register(command: .explorerDeleteSelection) { args in
            guard let path = args["path"] as? String else { return }
            guard let root = appState.workspace.currentDirectory?.standardizedFileURL else { return }
            do {
                let url = try PathValidator(projectRoot: root).validateAndResolve(path)
                appState.workspaceService.deleteItem(at: url)

                appState.fileEditor.closeTab(filePath: url.path)
                appState.workspace.removeOpenFile(url)
            } catch {
                appState.lastError = error.localizedDescription
            }
        }

        commandRegistry.register(command: .explorerRenameSelection) { args in
            guard let path = args["path"] as? String else { return }
            guard let newName = args["newName"] as? String else { return }
            guard let root = appState.workspace.currentDirectory?.standardizedFileURL else { return }
            do {
                let url = try PathValidator(projectRoot: root).validateAndResolve(path)

                if appState.fileEditor.isFileOpenAndDirty(filePath: url.path) {
                    appState.lastError = "Save changes before renaming an open file."
                    return
                }

                guard let newURL = appState.workspaceService.renameItem(at: url, to: newName) else { return }

                appState.fileEditor.renameTab(oldPath: url.path, newPath: newURL.path)

                appState.workspace.removeOpenFile(url)
                appState.workspace.addOpenFile(newURL)
            } catch {
                appState.lastError = error.localizedDescription
            }
        }

        commandRegistry.register(command: .explorerRevealInFinder) { args in
            guard let path = args["path"] as? String else { return }
            guard let root = appState.workspace.currentDirectory?.standardizedFileURL else { return }
            do {
                let url = try PathValidator(projectRoot: root).validateAndResolve(path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                appState.lastError = error.localizedDescription
            }
        }
        
        print("[CorePlugin] Initialized core UI components and commands")
    }
}
