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
    
    // MARK: - Editor Operations
    public static let editorFormat: CommandID = "editor.format"
}
