//
//  WorkspaceStateManager.swift
//  osx-ide
//
//  Created by Jack Trefon on 20/12/2025.
//

import SwiftUI
import Combine

/// Manages workspace state and operations
@MainActor
class WorkspaceStateManager: ObservableObject {
    @Published var currentDirectory: URL?
    @Published var openFiles: [String: URL] = [:]
    @Published var recentlyOpenedFiles: [URL] = []
    
    private let workspaceService: WorkspaceServiceProtocol
    private let fileDialogService: FileDialogServiceProtocol
    private let maxRecentFiles = 10
    
    init(workspaceService: WorkspaceServiceProtocol, fileDialogService: FileDialogServiceProtocol) {
        self.workspaceService = workspaceService
        self.fileDialogService = fileDialogService
        self.currentDirectory = workspaceService.currentDirectory
        
        // Restore previous session state
        if let savedPath = UserDefaults.standard.string(forKey: "LastOpenDirectory") {
            let url = URL(fileURLWithPath: savedPath)
            // Verify path exists
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                workspaceService.currentDirectory = url
                self.currentDirectory = url
            }
        } else {
            self.currentDirectory = workspaceService.currentDirectory
        }
    }
    
    // MARK: - Directory Operations
    
    /// Persist current directory to UserDefaults
    private func saveCurrentDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: "LastOpenDirectory")
    }
    
    /// Open file dialog for selecting files or directories
    /// - Parameter onFileSelected: Callback invoked when a file (not directory) is selected
    func openFileOrFolder(onFileSelected: ((URL) -> Void)? = nil) {
        guard let url = fileDialogService.openFileOrFolder() else { return }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            workspaceService.currentDirectory = url
            currentDirectory = url
            saveCurrentDirectory(url)
        } else {
            workspaceService.currentDirectory = url.deletingLastPathComponent()
            currentDirectory = workspaceService.currentDirectory
            if let cwd = currentDirectory {
                saveCurrentDirectory(cwd)
            }
            addToRecentlyOpened(url)
            onFileSelected?(url)
        }
    }
    
    /// Open folder dialog specifically for directories
    func openFolder() {
        guard let url = fileDialogService.openFolder() else { return }
        workspaceService.currentDirectory = url
        currentDirectory = url
        saveCurrentDirectory(url)
    }
    
    /// Navigate to parent directory
    func navigateToParent() {
        workspaceService.navigateToParent()
        currentDirectory = workspaceService.currentDirectory
        if let cwd = currentDirectory {
            saveCurrentDirectory(cwd)
        }
    }
    
    /// Navigate to subdirectory
    func navigateTo(subdirectory: String) {
        workspaceService.navigateTo(subdirectory: subdirectory)
        currentDirectory = workspaceService.currentDirectory
        if let cwd = currentDirectory {
            saveCurrentDirectory(cwd)
        }
    }
    
    // MARK: - File Management
    
    /// Create a new file in the current directory with validation
    func createFile(named name: String) {
        guard validateFileName(name) else {
            workspaceService.handleError(.invalidFilePath("Invalid file name: \(name)"))
            return
        }
        
        guard let directory = currentDirectory else {
            workspaceService.handleError(.invalidFilePath("No current directory selected"))
            return
        }
        
        workspaceService.createFile(named: name, in: directory)
    }
    
    /// Create a new folder in the current directory with validation
    func createFolder(named name: String) {
        guard validateFileName(name) else {
            workspaceService.handleError(.invalidFilePath("Invalid folder name: \(name)"))
            return
        }
        
        guard let directory = currentDirectory else {
            workspaceService.handleError(.invalidFilePath("No current directory selected"))
            return
        }
        
        workspaceService.createFolder(named: name, in: directory)
    }
    
    /// Check if path is valid and accessible
    func isValidPath(_ path: String) -> Bool {
        return workspaceService.isValidPath(path)
    }
    
    // MARK: - Recently Opened Files Management
    
    private func addToRecentlyOpened(_ url: URL) {
        // Remove if already exists
        recentlyOpenedFiles.removeAll { $0 == url }
        
        // Add to front
        recentlyOpenedFiles.insert(url, at: 0)
        
        // Limit to maxRecentFiles
        if recentlyOpenedFiles.count > AppConstants.FileSystem.maxRecentFiles {
            recentlyOpenedFiles = Array(recentlyOpenedFiles.prefix(AppConstants.FileSystem.maxRecentFiles))
        }
    }
    
    /// Remove file from recently opened list
    func removeFromRecentlyOpened(_ url: URL) {
        recentlyOpenedFiles.removeAll { $0 == url }
    }
    
    /// Clear recently opened files
    func clearRecentlyOpened() {
        recentlyOpenedFiles.removeAll()
    }
    
    // MARK: - Open Files Management
    
    /// Add file to open files list
    func addOpenFile(_ url: URL) {
        openFiles[url.lastPathComponent] = url
    }
    
    /// Remove file from open files list
    func removeOpenFile(_ url: URL) {
        openFiles.removeValue(forKey: url.lastPathComponent)
    }
    
    /// Check if file is currently open
    func isFileOpen(_ url: URL) -> Bool {
        return openFiles[url.lastPathComponent] != nil
    }
    
    /// Get all open files
    func getOpenFiles() -> [URL] {
        return Array(openFiles.values)
    }
    
    // MARK: - Workspace Information
    
    /// Get workspace display name
    var workspaceDisplayName: String {
        return currentDirectory?.lastPathComponent ?? "No Workspace"
    }
    
    /// Check if workspace is empty (no current directory)
    var isWorkspaceEmpty: Bool {
        return currentDirectory == nil
    }
    
    /// Validate file/folder name for security and correctness
    private func validateFileName(_ name: String) -> Bool {
        // Check for empty or whitespace-only names
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }
        
        // Check for path traversal attempts
        if trimmedName.contains("..") || trimmedName.contains("/") {
            return false
        }
        
        // Check for invalid characters
        guard trimmedName.rangeOfCharacter(from: AppConstants.Validation.invalidFileNameChars) == nil else {
            return false
        }
        
        // Check reserved names (Windows-style, but good practice)
        if AppConstants.Validation.reservedFileNames.contains(trimmedName.uppercased()) {
            return false
        }
        
        // Check name length
        if trimmedName.count > AppConstants.FileSystem.maxFileNameLength {
            return false
        }
        
        // Check for leading/trailing spaces or dots
        if trimmedName.hasPrefix(" ") || trimmedName.hasPrefix(".") || trimmedName.hasSuffix(" ") || trimmedName.hasSuffix(".") {
            return false
        }
        
        return true
    }
}
