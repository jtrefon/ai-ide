import SwiftUI
import AppKit
import Foundation

struct GoToSymbolOverlayView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var query: String = ""
    @State private var results: [WorkspaceSymbolLocation] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    @State private var searchService: WorkspaceSymbolSearchService?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Go to Symbol")
                    .font(.headline)

                TextField("Type a symbol…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 520)
                    .onSubmit {
                        openFirst(openToSide: NSEvent.modifierFlags.contains(.command))
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                Button("Close") {
                    close()
                }
            }

            List {
                ForEach(results) { item in
                    Button(action: {
                        open(item: item, openToSide: NSEvent.modifierFlags.contains(.command))
                    }) {
                        HStack(spacing: 10) {
                            Text(item.kind.rawValue)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .leading)

                            Text(item.name)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text("\(item.relativePath):\(item.line)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 760, minHeight: 420)
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 30)
        .onAppear {
            if searchService == nil {
                searchService = WorkspaceSymbolSearchService(codebaseIndexProvider: { DependencyContainer.shared.codebaseIndex })
            }
            query = ""
            refreshResults()
        }
        .onChange(of: query) { _, _ in
            debounceSearch()
        }
        .onExitCommand {
            close()
        }
    }

    private func debounceSearch() {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            refreshResults()
        }
    }

    private func refreshResults() {
        guard let root = appState.workspace.currentDirectory?.standardizedFileURL else {
            results = []
            return
        }

        guard let searchService else {
            results = []
            return
        }

        let currentFilePath = appState.fileEditor.selectedFile
        let currentLanguage = appState.fileEditor.editorLanguage
        let currentContent = appState.fileEditor.editorContent

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        isSearching = true
        defer { isSearching = false }

        results = searchService.search(
            query: trimmed,
            projectRoot: root,
            currentFilePath: currentFilePath,
            currentContent: currentContent,
            currentLanguage: currentLanguage,
            limit: 200
        )
    }

    private func openFirst(openToSide: Bool) {
        guard let first = results.first else { return }
        open(item: first, openToSide: openToSide)
    }

    private func open(item: WorkspaceSymbolLocation, openToSide: Bool) {
        guard let root = appState.workspace.currentDirectory?.standardizedFileURL else { return }

        do {
            let url = try PathValidator(projectRoot: root).validateAndResolve(item.relativePath)
            if openToSide {
                appState.fileEditor.openInOtherPane(from: url)
            } else {
                appState.loadFile(from: url)
            }
            appState.fileEditor.selectLine(item.line)
            close()
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func close() {
        searchTask?.cancel()
        isPresented = false
        query = ""
        results = []
        isSearching = false
    }
}
