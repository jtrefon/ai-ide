import SwiftUI

struct IndexStatusBarView: View {
    @ObservedObject private var appState: AppState
    @StateObject private var viewModel: IndexStatusBarViewModel

    init(appState: AppState, codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?, eventBus: EventBusProtocol) {
        self.appState = appState
        self._viewModel = StateObject(wrappedValue: IndexStatusBarViewModel(codebaseIndexProvider: codebaseIndexProvider, eventBus: eventBus))
    }

    @State private var isShowingMetricsInfo: Bool = false
    @State private var isShowingLanguagePicker: Bool = false

    private struct LanguageChoice: Identifiable {
        let id: String
        let title: String
        let languageIdentifier: String?
    }

    private var activeFilePath: String? {
        appState.fileEditor.selectedFile
    }

    private var activeLanguageLabel: String {
        guard let filePath = activeFilePath else { return "" }
        let effective = appState.effectiveLanguageIdentifier(forAbsoluteFilePath: filePath)
        return displayName(for: effective)
    }

    private var languageChoices: [LanguageChoice] {
        var choices: [LanguageChoice] = []
        choices.append(LanguageChoice(id: "auto", title: "Auto Detect", languageIdentifier: nil))

        // Core friendly list (keep simple; include React variants for common mis-detections).
        choices.append(LanguageChoice(id: "swift", title: "Swift", languageIdentifier: "swift"))
        choices.append(LanguageChoice(id: "javascript", title: "JavaScript", languageIdentifier: "javascript"))
        choices.append(LanguageChoice(id: "jsx", title: "JavaScript React", languageIdentifier: "jsx"))
        choices.append(LanguageChoice(id: "typescript", title: "TypeScript", languageIdentifier: "typescript"))
        choices.append(LanguageChoice(id: "tsx", title: "TypeScript React", languageIdentifier: "tsx"))
        choices.append(LanguageChoice(id: "python", title: "Python", languageIdentifier: "python"))
        choices.append(LanguageChoice(id: "html", title: "HTML", languageIdentifier: "html"))
        choices.append(LanguageChoice(id: "css", title: "CSS", languageIdentifier: "css"))
        choices.append(LanguageChoice(id: "json", title: "JSON", languageIdentifier: "json"))
        choices.append(LanguageChoice(id: "yaml", title: "YAML", languageIdentifier: "yaml"))
        choices.append(LanguageChoice(id: "markdown", title: "Markdown", languageIdentifier: "markdown"))
        choices.append(LanguageChoice(id: "text", title: "Plain Text", languageIdentifier: "text"))

        return choices
    }

    private func displayName(for languageIdentifier: String) -> String {
        let normalizedIdentifier = languageIdentifier.lowercased()
        let displayNamesByIdentifier: [String: String] = [
            "swift": "Swift",
            "javascript": "JavaScript",
            "jsx": "JavaScript React",
            "typescript": "TypeScript",
            "tsx": "TypeScript React",
            "python": "Python",
            "html": "HTML",
            "css": "CSS",
            "json": "JSON",
            "yaml": "YAML",
            "yml": "YAML",
            "markdown": "Markdown",
            "md": "Markdown",
            "text": "Plain Text"
        ]

        return displayNamesByIdentifier[normalizedIdentifier] ?? "Plain Text"
    }

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.isIndexing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(viewModel.statusText)
                .font(.caption)
                .lineLimit(1)

            Spacer(minLength: 8)

            if activeFilePath != nil {
                Button {
                    isShowingLanguagePicker.toggle()
                } label: {
                    Text(activeLanguageLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingLanguagePicker, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Select Language Mode")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(languageChoices) { choice in
                                Button {
                                    guard let filePath = activeFilePath else { return }
                                    appState.setLanguageOverride(forAbsoluteFilePath: filePath, languageIdentifier: choice.languageIdentifier)
                                    isShowingLanguagePicker = false
                                } label: {
                                    Text(choice.title)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .frame(width: 240)
                }
            }

            HStack(spacing: 6) {
                Text(viewModel.metricsText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Button {
                    isShowingMetricsInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingMetricsInfo, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Index Metrics")
                            .font(.headline)
                        Text("C = Classes")
                        Text("F = Functions")
                        Text("S = Total symbols")
                        Text("Q = Average quality score (0-100)")
                        Text("M = Memories (LT = Long-term)")
                        Text("DB = Database size")
                    }
                    .padding(12)
                    .frame(width: 260)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}
