//
//  FileTreeDialogCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 11/01/2026.
//

import Foundation
import AppKit

/// Handles dialog interactions for the file tree
@MainActor
final class FileTreeDialogCoordinator {
    
    /// Prompts user for renaming an item
    func promptForRename(initialName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("file_tree.rename.title", comment: "")
        alert.informativeText = NSLocalizedString("file_tree.rename.info", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("file_tree.rename.button", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("common.cancel", comment: ""))

        let textField = NSTextField(string: initialName)
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    /// Prompts user for creating a new item
    func promptForNewItem(title: String, informativeText: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("file_tree.create.button", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("common.cancel", comment: ""))

        let textField = NSTextField(string: "")
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
