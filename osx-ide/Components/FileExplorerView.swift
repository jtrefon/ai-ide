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

    // State for new file/folder creation
    @State private var isShowingNewFileSheet = false
    @State private var isShowingNewFolderSheet = false
    @State private var newFileName: String = ""
    @State private var newFolderName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Explorer")
                    .font(.headline)
                    .padding(.horizontal)
                Spacer()
                Button(action: {
                    refreshToken += 1
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(BorderlessButtonStyle())
                .padding(.horizontal)
            }
            .frame(height: 30)
            .nativeGlassBackground(.header)

            // Modern macOS v26 file tree with subtle styling
            ModernFileTreeView(
                rootURL: appState.currentDirectory ?? FileManager.default.homeDirectoryForCurrentUser,
                searchQuery: $searchQuery,
                expandedRelativePaths: $expandedRelativePaths,
                selectedRelativePath: $selectedRelativePath,
                refreshToken: refreshToken,
                onOpenFile: { url in
                    appState.loadFile(from: url)
                }
            )
            .background(Color(NSColor.controlBackgroundColor))
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
