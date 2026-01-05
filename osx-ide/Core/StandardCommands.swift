//
//  StandardCommands.swift
//  osx-ide
//
//  Created by Jack Trefon on 21/12/2025.
//

import Foundation

/// Defines the standard set of commands that the IDE supports.
/// Plugins can intercept these or the UI can trigger them.
extension CommandID {
    // MARK: - File Operations
    public static let fileNew: CommandID = "file.new"
    public static let projectNew: CommandID = "project.new"
    public static let fileOpen: CommandID = "file.open"
    public static let fileOpenFolder: CommandID = "file.openFolder"
    public static let fileSave: CommandID = "file.save"
    public static let fileSaveAs: CommandID = "file.saveAs"
    
    // MARK: - File Explorer
    public static let explorerOpenSelection: CommandID = "explorer.openSelection"
    public static let explorerDeleteSelection: CommandID = "explorer.deleteSelection"
    public static let explorerRenameSelection: CommandID = "explorer.renameSelection"
    public static let explorerRevealInFinder: CommandID = "explorer.revealInFinder"
    
    // MARK: - Editor Operations
    public static let editorFormat: CommandID = "editor.format"

    public static let editorTabsCloseActive: CommandID = "editor.tabs.closeActive"
    public static let editorTabsCloseAll: CommandID = "editor.tabs.closeAll"
    public static let editorTabsNext: CommandID = "editor.tabs.next"
    public static let editorTabsPrevious: CommandID = "editor.tabs.previous"

    public static let editorSplitRight: CommandID = "editor.splitRight"
    public static let editorSplitDown: CommandID = "editor.splitDown"
    public static let editorFocusNextGroup: CommandID = "editor.focusNextGroup"

    public static let editorFind: CommandID = "editor.find"
    public static let editorReplace: CommandID = "editor.replace"
}
