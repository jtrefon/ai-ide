//
//  FileExplorerView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI

struct FileExplorerView: View {
    @ObservedObject var appState: AppState
    @State private var searchQuery: String = ""
    @State private var expandedRelativePaths: Set<String> = []
    @State private var selectedRelativePath: String? = nil
    @State private var refreshToken: Int = 0

    @AppStorage("ShowHiddenFilesInFileTree") private var showHiddenFiles: Bool = false

    // State for new file/folder creation
    @State private var isShowingNewFileSheet = false
    @State private var isShowingNewFolderSheet = false
    @State private var newFileName: String = ""
    @State private var newFolderName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            // Header with Search Input
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    TextField("Search...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                Button(action: {
                    refreshToken += 1
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12)) 
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Refresh")
            }
            .padding(8)
            .frame(height: 48) // Slightly taller for search bar
            .background(Color(NSColor.windowBackgroundColor))
            // Modern macOS v26 file tree with subtle styling
            ModernFileTreeView(
                rootURL: appState.currentDirectory ?? FileManager.default.temporaryDirectory,
                searchQuery: $searchQuery,
                expandedRelativePaths: $expandedRelativePaths,
                selectedRelativePath: $selectedRelativePath,
                showHiddenFiles: showHiddenFiles,
                refreshToken: refreshToken,
                onOpenFile: { url in
                    appState.loadFile(from: url)
                }
            )
            .background(Color(NSColor.windowBackgroundColor))
            .contextMenu {
                Button("New File") {
                    newFileName = ""
                    isShowingNewFileSheet = true
                }
                Button("New Folder") {
                    newFolderName = ""
                    isShowingNewFolderSheet = true
                }
            }
            .sheet(isPresented: $isShowingNewFileSheet) {
                VStack(spacing: 20) {
                    Text("Create New File")
                        .font(.headline)
                    TextField("File name", text: $newFileName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                        .onSubmit {
                            createNewFile()
                        }
                    HStack {
                        Button("Cancel") {
                            isShowingNewFileSheet = false
                        }
                        Spacer()
                        Button("Create") {
                            createNewFile()
                        }
                        .disabled(newFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .frame(width: 300)
            }
            .sheet(isPresented: $isShowingNewFolderSheet) {
                VStack(spacing: 20) {
                    Text("Create New Folder")
                        .font(.headline)
                    TextField("Folder name", text: $newFolderName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                        .onSubmit {
                            createNewFolder()
                        }
                    HStack {
                        Button("Cancel") {
                            isShowingNewFolderSheet = false
                        }
                        Spacer()
                        Button("Create") {
                            createNewFolder()
                        }
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .frame(width: 300)
            }
        }
        .frame(minWidth: 200)
        .onAppear {
            syncSelectionFromAppState()
        }
        .onChange(of: appState.currentDirectory) {
            refreshToken += 1
            syncSelectionFromAppState()
        }
        .onChange(of: appState.selectedFile) {
            syncSelectionFromAppState()
        }
    }

    private func syncSelectionFromAppState() {
        guard let rootURL = appState.currentDirectory?.standardizedFileURL ?? FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL as URL? else {
            selectedRelativePath = nil
            return
        }
        guard let selectedFilePath = appState.selectedFile else {
            selectedRelativePath = nil
            return
        }
        let selectedURL = URL(fileURLWithPath: selectedFilePath).standardizedFileURL
        let rootPath = rootURL.path
        let selectedPath = selectedURL.path
        guard selectedPath.hasPrefix(rootPath) else {
            selectedRelativePath = nil
            return
        }
        var relative = String(selectedPath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        selectedRelativePath = relative.isEmpty ? nil : relative
    }

    private func createNewFile() {
        defer { isShowingNewFileSheet = false }
        let trimmedName = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        appState.createFile(name: trimmedName)
        refreshToken += 1
    }

    private func createNewFolder() {
        defer { isShowingNewFolderSheet = false }
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        appState.createFolder(name: trimmedName)
        refreshToken += 1
    }
}

#Preview {
    FileExplorerView(appState: DependencyContainer.shared.makeAppState())
        .frame(width: 250, height: 400)
}
