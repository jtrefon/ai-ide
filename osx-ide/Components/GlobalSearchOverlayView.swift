import SwiftUI

struct GlobalSearchOverlayView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var resultsByFile: [(file: String, matches: [WorkspaceSearchMatch])] = []
    @State private var searchTask: Task<Void, Never>?

    private let searchService = WorkspaceSearchService(codebaseIndexProvider: { DependencyContainer.shared.codebaseIndex })

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Search")
                    .font(.headline)
                TextField("Find in workspace", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 420)
                    .onSubmit {
                        triggerSearch()
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
                ForEach(resultsByFile, id: \.file) { group in
                    Section(group.file) {
                        ForEach(group.matches) { match in
                            Button(action: {
                                open(match: match, openToSide: false)
                            }) {
                                HStack {
                                    Text("\(match.line)")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .trailing)

                                    Text(match.snippet)
                                        .lineLimit(2)

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(minWidth: 760, minHeight: 420)
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 30)
        .onAppear {
            if query.isEmpty {
                query = ""
            }
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
            try? await Task.sleep(nanoseconds: 250_000_000)
            triggerSearch()
        }
    }

    private func triggerSearch() {
        guard let root = appState.workspace.currentDirectory?.standardizedFileURL else {
            resultsByFile = []
            return
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty {
            resultsByFile = []
            return
        }

        searchTask?.cancel()
        searchTask = Task { @MainActor in
            isSearching = true
            defer { isSearching = false }

            let matches = await searchService.search(pattern: needle, projectRoot: root, limit: 400)
            resultsByFile = Self.group(matches)
        }
    }

    private func open(match: WorkspaceSearchMatch, openToSide: Bool) {
        guard let root = appState.workspace.currentDirectory?.standardizedFileURL else { return }

        do {
            let url = try PathValidator(projectRoot: root).validateAndResolve(match.relativePath)
            if openToSide {
                appState.fileEditor.openInOtherPane(from: url)
            } else {
                appState.loadFile(from: url)
            }
            appState.fileEditor.selectLine(match.line)
            close()
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func close() {
        searchTask?.cancel()
        isPresented = false
        isSearching = false
        query = ""
        resultsByFile = []
    }

    private static func group(_ matches: [WorkspaceSearchMatch]) -> [(file: String, matches: [WorkspaceSearchMatch])] {
        let grouped = Dictionary(grouping: matches, by: { $0.relativePath })
        let sortedKeys = grouped.keys.sorted()
        return sortedKeys.map { key in
            let sorted = (grouped[key] ?? []).sorted { $0.line < $1.line }
            return (file: key, matches: sorted)
        }
    }
}
