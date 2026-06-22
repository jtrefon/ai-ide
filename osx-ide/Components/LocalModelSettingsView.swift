import SwiftUI

struct LocalModelSettingsView: View {
    @ObservedObject var viewModel: LocalModelSettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Offline Mode (disable OpenRouter)", isOn: $viewModel.offlineModeEnabled)
                Toggle("Turbo Quant (4-bit KV Cache)", isOn: $viewModel.turboQuantEnabled)
            } header: {
                Text("Local Models")
            }

            Section {
                Slider(value: $viewModel.contextLength, in: 2048...131072, step: 1024) {
                    Text("Context Length: \(Int(viewModel.contextLength)) tokens")
                }
            }

            Section {
                Picker("Model", selection: $viewModel.selectedModelId) {
                    Text("None").tag("")
                    ForEach(viewModel.models) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }

                ForEach(viewModel.models) { model in
                    LocalModelRow(
                        model: model,
                        isInstalled: viewModel.isInstalled(model),
                        isSelected: viewModel.selectedModelId == model.id,
                        isDownloading: viewModel.isDownloading,
                        onSelect: {
                            viewModel.selectModel(model)
                        },
                        onDownload: {
                            Task { await viewModel.downloadModel(model) }
                        },
                        onDelete: {
                            viewModel.deleteModel(model)
                        }
                    )
                }

                LocalModelStatusLine(
                    status: viewModel.status,
                    progressFraction: viewModel.progressFraction,
                    currentFileName: viewModel.currentFileName,
                    progressText: viewModel.progressText,
                    isDownloading: viewModel.isDownloading
                )
            }
        }
        .formStyle(.grouped)
        .onAppear {
            viewModel.refreshCatalog()
        }
    }
}

private struct LocalModelRow: View {
    let model: LocalModelDefinition
    let isInstalled: Bool
    let isSelected: Bool
    let isDownloading: Bool

    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.body)

                    Text(model.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Text("Selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Select") {
                    onSelect()
                }
                .buttonStyle(.bordered)
                .disabled(!isInstalled || isDownloading)

                Button(isInstalled ? "Re-download" : "Download") {
                    onDownload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloading)

                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .disabled(!isInstalled || isDownloading)
            }

            Divider()
                .opacity(0.2)
        }
    }
}

private struct LocalModelStatusLine: View {
    let status: LocalModelSettingsViewModel.Status
    let progressFraction: Double
    let currentFileName: String?
    let progressText: String?
    let isDownloading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isDownloading {
                ProgressView(value: progressFraction)
                    .frame(width: 420)

                if let currentFileName {
                    HStack {
                        Text(currentFileName)
                        Spacer()
                        if let progressText {
                            Text(progressText)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 420)
                }
            }

            Text(status.message)
                .font(.caption)
                .foregroundStyle(color(for: status.kind))
        }
    }

    private func color(for kind: LocalModelSettingsViewModel.Status.Kind) -> Color {
        switch kind {
        case .idle:
            return .secondary
        case .loading:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .yellow
        case .error:
            return .red
        }
    }
}
