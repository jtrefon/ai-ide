import SwiftUI

struct EmbeddingModelSettingsView: View {
    @ObservedObject var viewModel: EmbeddingModelSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Embedding Models (for Semantic Search)")
                .font(.headline)

            Text("These models are used for semantic search in the codebase index. Smaller models are faster, larger models are more accurate. Bundled models are included with the app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $viewModel.selectedModelId) {
                Text("None (fallback to hashing)")
                    .tag("")

                ForEach(viewModel.models) { model in
                    Text(model.name)
                        .tag(model.id)
                }
            }
            .labelsHidden()
            .frame(width: 420)

            VStack(alignment: .leading, spacing: 10) {
                // Bundled models section
                if !EmbeddingModelCatalog.bundledModels.isEmpty {
                    Text("Bundled Models (included with app)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    
                    ForEach(EmbeddingModelCatalog.bundledModels) { model in
                        EmbeddingModelRow(
                            model: model,
                            isBundled: true,
                            isInstalled: true,
                            isSelected: viewModel.selectedModelId == model.id,
                            isDownloading: viewModel.isDownloading,
                            onSelect: {
                                viewModel.selectModel(model)
                            },
                            onDownload: nil,  // No download for bundled models
                            onDelete: nil     // No delete for bundled models
                        )
                    }
                }
            }

            EmbeddingModelStatusLine(
                status: viewModel.status,
                progressFraction: viewModel.progressFraction,
                currentFileName: viewModel.currentFileName,
                isDownloading: viewModel.isDownloading
            )
        }
        .onAppear {
            viewModel.refreshCatalog()
        }
        .alert("Model Change Requires Reindex", isPresented: $viewModel.showReindexConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelModelChange()
            }
            Button("Reindex Now") {
                viewModel.confirmModelChange()
            }
        } message: {
            Text("Switching embedding models requires rebuilding the index to avoid data corruption. This will re-embed all files with the new model. Continue?")
        }
    }
}

private struct EmbeddingModelRow: View {
    let model: EmbeddingModelDefinition
    let isBundled: Bool
    let isInstalled: Bool
    let isSelected: Bool
    let isDownloading: Bool

    let onSelect: () -> Void
    let onDownload: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.body)
                        
                        if isBundled {
                            Text("Bundled")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Text("\(model.dimensions)D")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(model.sizeDisplayString)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !isBundled && isInstalled {
                            Text("Downloaded")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                Button("Use") {
                    onSelect()
                }
                .buttonStyle(.bordered)
                .disabled(!isInstalled || isDownloading || isSelected)

                // Only show download/delete for non-bundled models
                if !isBundled {
                    if let onDownload = onDownload {
                        Button(isInstalled ? "Re-download" : "Download") {
                            onDownload()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDownloading)
                    }

                    if let onDelete = onDelete {
                        Button("Delete") {
                            onDelete()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isInstalled || isDownloading)
                    }
                }
            }

            Divider()
                .opacity(0.2)
        }
    }
}

private struct EmbeddingModelStatusLine: View {
    let status: EmbeddingModelSettingsViewModel.Status
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

    private func color(for kind: EmbeddingModelSettingsViewModel.Status.Kind) -> Color {
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
