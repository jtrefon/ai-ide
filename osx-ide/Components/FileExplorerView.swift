//
//  FileExplorerView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI

struct FileExplorerView<Context: IDEContext & ObservableObject>: View {
    @ObservedObject var context: Context
    @State private var searchQuery: String = ""
    @State private var refreshToken: Int = 0

    private var showHiddenFiles: Bool { context.showHiddenFilesInFileTree }

    // State for new file/folder creation
    @State private var isShowingNewFileSheet = false
    @State private var isShowingNewFolderSheet = false
    @State private var newFileName: String = ""
    @State private var newFolderName: String = ""

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            // Header with Search Input
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: max(10, context.ui.fontSize - 2)))
                        .foregroundColor(.secondary)

                    TextField(localized("file_explorer.search.placeholder"), text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: CGFloat(context.ui.fontSize)))

                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: max(10, context.ui.fontSize - 2)))
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
                        .font(.system(size: max(10, context.ui.fontSize - 2)))
                }
                .buttonStyle(BorderlessButtonStyle())
                .help(localized("file_explorer.refresh_help"))
            }
            .padding(8)
            .frame(height: 48) // Slightly taller for search bar
            .background(Color(NSColor.windowBackgroundColor))
            // Modern macOS v26 file tree with subtle styling
            ModernFileTreeView(
                rootURL: context.workspace.currentDirectory ?? FileManager.default.temporaryDirectory,
                searchQuery: $searchQuery,
                expandedRelativePaths: Binding(
                    get: { context.fileTreeExpandedRelativePaths },
                    set: { context.fileTreeExpandedRelativePaths = $0 }
                ),
                selectedRelativePath: Binding(
                    get: { context.fileTreeSelectedRelativePath },
                    set: { context.fileTreeSelectedRelativePath = $0 }
                ),
                showHiddenFiles: showHiddenFiles,
                refreshToken: refreshToken,
                onOpenFile: { url in
                    Task {
                        try? await context.commandRegistry.execute(
                            .explorerOpenSelection,
                            args: ExplorerPathArgs(path: url.path)
                        )
                    }
                },
                onCreateFile: { directory, name in
                    context.workspaceService.createFile(named: name, in: directory)
                    refreshToken += 1
                },
                onCreateFolder: { directory, name in
                    context.workspaceService.createFolder(named: name, in: directory)
                    refreshToken += 1
                },
                onDeleteItem: { url in
                    Task {
                        try? await context.commandRegistry.execute(
                            .explorerDeleteSelection,
                            args: ExplorerPathArgs(path: url.path)
                        )
                        await MainActor.run {
                            refreshToken += 1
                            syncSelectionFromAppState()
                        }
                    }
                },
                onRenameItem: { url, newName in
                    Task {
                        try? await context.commandRegistry.execute(
                            .explorerRenameSelection,
                            args: ExplorerRenameArgs(path: url.path, newName: newName)
                        )
                        await MainActor.run {
                            refreshToken += 1
                            syncSelectionFromAppState()
                        }
                    }
                },
                onRevealInFinder: { url in
                    Task {
                        try? await context.commandRegistry.execute(
                            .explorerRevealInFinder,
                            args: ExplorerPathArgs(path: url.path)
                        )
                    }
                },
                fontSize: context.ui.fontSize,
                fontFamily: context.ui.fontFamily
            )
            .background(Color(NSColor.windowBackgroundColor))
            // SwiftUI context menu disabled to allow NSOutlineView native menu
            // .contextMenu {
            //     Button(localized("file_tree.context.new_file")) {
            //         newFileName = ""
            //         isShowingNewFileSheet = true
            //     }
            //     Button(localized("file_tree.context.new_folder")) {
            //         newFolderName = ""
            //         isShowingNewFolderSheet = true
            //     }
            // }
            .sheet(isPresented: $isShowingNewFileSheet) {
                VStack(spacing: 20) {
                    Text(localized("file_tree.create_file.title"))
                        .font(.headline)
                    TextField(localized("file_tree.create_file.name_placeholder"), text: $newFileName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                        .onSubmit {
                            createNewFile()
                        }
                    HStack {
                        Button(localized("common.cancel")) {
                            isShowingNewFileSheet = false
                        }
                        Spacer()
                        Button(localized("common.create")) {
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
                    Text(localized("file_tree.create_folder.title"))
                        .font(.headline)
                    TextField(localized("file_tree.create_folder.name_placeholder"), text: $newFolderName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                        .onSubmit {
                            createNewFolder()
                        }
                    HStack {
                        Button(localized("common.cancel")) {
                            isShowingNewFolderSheet = false
                        }
                        Spacer()
                        Button(localized("common.create")) {
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
        .onChange(of: context.workspace.currentDirectory) {
            refreshToken += 1
            syncSelectionFromAppState()
        }
        .onChange(of: context.fileTreeRefreshToken) {
            refreshToken = context.fileTreeRefreshToken
        }
        .onChange(of: context.fileEditor.selectedFile) {
            syncSelectionFromAppState()
        }
    }

    private func syncSelectionFromAppState() {
        guard let selectedFilePath = context.fileEditor.selectedFile else {
            context.fileTreeSelectedRelativePath = nil
            return
        }
        let selectedURL = URL(fileURLWithPath: selectedFilePath)
        context.fileTreeSelectedRelativePath = context.relativePath(for: selectedURL)
    }

    private func createNewFile() {
        defer { isShowingNewFileSheet = false }
        let trimmedName = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        context.workspace.createFile(named: trimmedName)
        refreshToken += 1
    }

    private func createNewFolder() {
        defer { isShowingNewFolderSheet = false }
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        context.workspace.createFolder(named: trimmedName)
        refreshToken += 1
    }
}

struct FileExplorerView_Previews: PreviewProvider {
    static var previews: some View {
        FileExplorerView(context: DependencyContainer().makeAppState())
            .frame(width: 250, height: 400)
    }
}
