import SwiftUI

struct LocalModelSettingsView: View {
    @ObservedObject var viewModel: LocalModelSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Offline Mode (disable OpenRouter)", isOn: $viewModel.offlineModeEnabled)
                .toggleStyle(.switch)

            Text("Available local models: \(viewModel.models.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $viewModel.selectedModelId) {
                Text("None")
                    .tag("")

                ForEach(viewModel.models) { model in
                    Text(model.displayName)
                        .tag(model.id)
                }
            }
            .labelsHidden()
            .frame(width: 420)

            VStack(alignment: .leading, spacing: 10) {
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
            }

            LocalModelStatusLine(
                status: viewModel.status,
                progressFraction: viewModel.progressFraction,
                currentFileName: viewModel.currentFileName,
                isDownloading: viewModel.isDownloading
            )
        }
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
    let isDownloading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isDownloading {
                ProgressView(value: progressFraction)
                    .frame(width: 420)

                if let currentFileName {
                    Text(currentFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
