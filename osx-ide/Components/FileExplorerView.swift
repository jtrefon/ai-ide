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

struct FileItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    let isDirectory: Bool
    let name: String
    let level: Int

    init(url: URL, isDirectory: Bool, level: Int = 0) {
        self.id = url
        self.url = url
        self.isDirectory = isDirectory
        self.name = url.lastPathComponent
        self.level = level
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        return lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

struct FileItemRow: View {
    let item: FileItem
    @ObservedObject var appState: AppState
    @Binding var expandedItems: Set<URL>
    @Binding var selectedFileItem: FileItem?
    let level: Int

    @State private var childItems: [FileItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Indentation
                ForEach(0..<item.level, id: \.self) { _ in
                    Spacer().frame(width: 16)
                }

                // Expand/Collapse button for directories
                if item.isDirectory {
                    Button(action: {
                        toggleExpansion()
                    }) {
                        Image(systemName: expandedItems.contains(item.url) ? "chevron.down" : "chevron.right")
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Spacer for files to align with directory icons
                    Spacer().frame(width: 16)
                }

                // File/Folder icon
                Image(systemName: item.isDirectory ? "folder" : fileIcon(for: item.name))
                    .foregroundColor(item.isDirectory ? .blue : .secondary)

                // File/Folder name
                Text(item.name)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            // Handle double-click with higher priority to prevent single-click from firing
            .highPriorityGesture(
                TapGesture(count: 2).onEnded {
                    if item.isDirectory {
                        toggleExpansion()
                    } else {
                        openFile(item.url)
                    }
                }
            )
            // Single click selects (highlights) only
            .gesture(
                TapGesture(count: 1).onEnded {
                    selectedFileItem = item
                }
            )
            .contextMenu {
                if !item.isDirectory {
                    Button("Open") {
                        openFile(item.url)
                    }
                }
                // Add other context menu items as needed
            }
            .background(
                Group {
                    if selectedFileItem == item {
                        Color.accentColor.opacity(0.15)
                    } else {
                        Color.clear
                    }
                }
            )

            // Child items (if expanded)
            if item.isDirectory && expandedItems.contains(item.url) {
                ForEach(childItems, id: \.url) { childItem in
                    FileItemRow(item: childItem,
                               appState: appState,
                               expandedItems: $expandedItems,
                               selectedFileItem: $selectedFileItem,
                               level: childItem.level)
                }
            }
        }
    }

    private func toggleExpansion() {
        if expandedItems.contains(item.url) {
            expandedItems.remove(item.url)
        } else {
            expandedItems.insert(item.url)
            loadChildItems()
        }
    }

    private func loadChildItems() {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: item.url, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return
        }

        childItems = contents.map { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return FileItem(url: url, isDirectory: isDirectory, level: item.level + 1)
        }.sorted { item1, item2 in
            // Directories first, then files
            if item1.isDirectory && !item2.isDirectory {
                return true
            } else if !item1.isDirectory && item2.isDirectory {
                return false
            } else {
                // Both are directories or both are files, sort alphabetically
                return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }
        }
    }

    private func openFile(_ url: URL) {
        appState.loadFile(from: url)
    }

    private func fileIcon(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":
            return "swift"
        case "js", "jsx":
            return "j.square"
        case "ts", "tsx":
            return "t.square"
        case "py":
            return "p.square"
        case "html":
            return "h.square"
        case "css":
            return "c.square"
        case "json":
            return "curlybraces"
        case "md":
            return "doc.plaintext"
        default:
            return "doc"
        }
    }
}

#Preview {
    FileExplorerView(appState: DependencyContainer.shared.makeAppState())
        .frame(width: 250, height: 400)
}

