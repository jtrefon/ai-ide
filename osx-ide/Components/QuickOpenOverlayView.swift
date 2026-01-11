import SwiftUI
import AppKit

struct QuickOpenOverlayView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var workspace: WorkspaceStateManager
    @ObservedObject private var fileEditor: FileEditorStateManager
    @Binding var isPresented: Bool

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    @State private var query: String = ""
    @State private var results: [String] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    init(appState: AppState, isPresented: Binding<Bool>) {
        self.appState = appState
        self._workspace = ObservedObject(wrappedValue: appState.workspace)
        self._fileEditor = ObservedObject(wrappedValue: appState.fileEditor)
        self._isPresented = isPresented
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(localized("quick_open.title"))
                    .font(.headline)

                TextField(localized("quick_open.placeholder"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: AppConstants.Overlay.textFieldMinWidth)
                    .onSubmit {
                        openFirst(openToSide: NSEvent.modifierFlags.contains(.command))
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                Button(localized("common.close")) {
                    close()
                }
            }

            List {
                if !recentCandidates().isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section(localized("quick_open.recent")) {
                        ForEach(recentCandidates(), id: \.self) { path in
                            Button(action: { open(path: path, openToSide: false) }) {
                                Text(path)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section(localized("quick_open.results")) {
                    ForEach(results, id: \.self) { path in
                        Button(action: { open(path: path, openToSide: NSEvent.modifierFlags.contains(.command)) }) {
                            Text(path)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minWidth: AppConstants.Overlay.listMinWidth, minHeight: AppConstants.Overlay.listMinHeight)
        }
        .padding(AppConstants.Overlay.containerPadding)
        .background(.regularMaterial)
        .cornerRadius(AppConstants.Overlay.containerCornerRadius)
        .shadow(radius: AppConstants.Overlay.containerShadowRadius)
        .onAppear {
            query = ""
            results = []
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
            try? await Task.sleep(nanoseconds: AppConstants.Time.quickSearchDebounceNanoseconds)
            await refreshResults()
        }
    }

    private func refreshResults() async {
        guard let root = workspace.currentDirectory?.standardizedFileURL else {
            results = []
            return
        }

        let (fileQuery, _) = Self.parseQuery(query)
        let trimmed = fileQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            results = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        let settingsStore = SettingsStore(userDefaults: .standard)
        if let index = appState.codebaseIndex,
           settingsStore.bool(forKey: AppConstants.Storage.codebaseIndexEnabledKey, default: true),
           let matches = try? await index.findIndexedFiles(query: trimmed, limit: 50) {
            results = matches.map { $0.path }
            return
        }

        results = fallbackFindFiles(query: trimmed, root: root, limit: 50)
    }

    private func fallbackFindFiles(query: String, root: URL, limit: Int) -> [String] {
        QuickOpenFileFinder().findFiles(query: query, root: root, limit: limit)
    }

    private func recentCandidates() -> [String] {
        guard let root = workspace.currentDirectory?.standardizedFileURL else { return [] }
        var output: [String] = []
        output.reserveCapacity(10)

        for url in workspace.recentlyOpenedFiles {
            if output.count >= 10 { break }
            guard url.path.hasPrefix(root.path + "/") else { continue }
            output.append(String(url.path.dropFirst(root.path.count + 1)))
        }

        return output
    }

    private func openFirst(openToSide: Bool) {
        guard let first = results.first else { return }
        open(path: first, openToSide: openToSide)
    }

    private func open(path: String, openToSide: Bool) {
        guard let root = workspace.currentDirectory?.standardizedFileURL else { return }
        let (_, line) = Self.parseQuery(query)

        do {
            let url = try appState.workspaceService.makePathValidator(projectRoot: root).validateAndResolve(path)
            if openToSide {
                fileEditor.openInOtherPane(from: url)
            } else {
                appState.loadFile(from: url)
            }
            if let line {
                fileEditor.selectLine(line)
            }
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

    static func parseQuery(_ raw: String) -> (fileQuery: String, line: Int?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", nil) }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return (trimmed, nil) }

        if let last = parts.last, let line = Int(last) {
            let file = parts.dropLast().joined(separator: ":")
            return (String(file), max(1, line))
        }

        return (trimmed, nil)
    }
}
