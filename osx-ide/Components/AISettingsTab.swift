//
//  AISettingsTab.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import SwiftUI

struct AISettingsTab: View {
    @ObservedObject var viewModel: OpenRouterSettingsViewModel
    @StateObject private var localModelViewModel = LocalModelSettingsViewModel()
    @State private var showAdvanced = false

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard(
                    title: "Provider",
                    subtitle: "Choose which AI provider the IDE uses."
                ) {
                    SettingsRow(
                        title: "Provider",
                        subtitle: "Remote uses OpenRouter. Local uses the on-device model.",
                        systemImage: "sparkles"
                    ) {
                        Picker("", selection: $localModelViewModel.provider) {
                            Text("Remote").tag(AIProvider.remote)
                            Text("Local").tag(AIProvider.local)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                }

                SettingsCard(
                    title: "On-device model",
                    subtitle: "Offline-capable model settings and download configuration."
                ) {
                    SettingsRow(
                        title: "Model",
                        subtitle: "Select the on-device model to download and run.",
                        systemImage: "shippingbox"
                    ) {
                        Picker("", selection: $localModelViewModel.selectedModelId) {
                            ForEach(LocalModelCatalog.items) { item in
                                if let size = localModelViewModel.modelSizeDisplayString(modelId: item.id) {
                                    Text("\(item.displayName) — \(size)").tag(item.id)
                                } else {
                                    Text(item.displayName).tag(item.id)
                                }
                            }
                        }
                        .frame(width: 360)
                    }

                    SettingsRow(
                        title: "Enable",
                        subtitle: "Enable the on-device model runtime.",
                        systemImage: "cpu"
                    ) {
                        Toggle("", isOn: $localModelViewModel.localModelEnabled)
                            .toggleStyle(.switch)
                    }

                    SettingsRow(
                        title: "Quantization",
                        subtitle: "4-bit is smaller and faster. 8-bit is higher quality.",
                        systemImage: "gauge"
                    ) {
                        Picker("", selection: $localModelViewModel.quantization) {
                            ForEach(localModelViewModel.supportedQuantizationsForSelectedModel(), id: \.self) { quant in
                                Text(quant == .q4 ? "4-bit" : "8-bit").tag(quant)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }

                    SettingsRow(
                        title: "Allow remote fallback",
                        subtitle: "If local model is unavailable, allow remote provider to answer.",
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        Toggle("", isOn: $localModelViewModel.allowRemoteFallback)
                            .toggleStyle(.switch)
                    }

                    SettingsRow(
                        title: "Context budget",
                        subtitle: "Max tokens to send (clamped to the selected model's context window).",
                        systemImage: "text.alignleft"
                    ) {
                        VStack(alignment: .trailing, spacing: 6) {
                            let maxTokens = Double(localModelViewModel.maxContextBudgetTokensForSelectedModel())
                            let minTokens = 512.0
                            Slider(
                                value: $localModelViewModel.contextBudgetTokensDraft,
                                in: minTokens...maxTokens,
                                step: 128,
                                onEditingChanged: { isEditing in
                                    if !isEditing {
                                        localModelViewModel.applyContextBudgetDraft()
                                    }
                                }
                            )
                            .frame(width: 240)

                            Text("\(Int(localModelViewModel.contextBudgetTokensDraft)) tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsRow(
                        title: "Answer token budget",
                        subtitle: "Target maximum tokens for the final answer (model is instructed to stay within this budget).",
                        systemImage: "text.bubble"
                    ) {
                        VStack(alignment: .trailing, spacing: 6) {
                            let minTokens = 64.0
                            let maxTokens = 2048.0
                            Slider(
                                value: $localModelViewModel.maxAnswerTokensDraft,
                                in: minTokens...maxTokens,
                                step: 64,
                                onEditingChanged: { isEditing in
                                    if !isEditing {
                                        localModelViewModel.applyMaxAnswerTokensDraft()
                                    }
                                }
                            )
                            .frame(width: 240)

                            Text("\(Int(localModelViewModel.maxAnswerTokensDraft)) tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsRow(
                        title: "Reasoning token budget",
                        subtitle: "Target maximum tokens for <ide_reasoning>. Reasoning is not stored in history.",
                        systemImage: "brain"
                    ) {
                        VStack(alignment: .trailing, spacing: 6) {
                            let minTokens = 64.0
                            let maxTokens = 4096.0
                            Slider(
                                value: $localModelViewModel.maxReasoningTokensDraft,
                                in: minTokens...maxTokens,
                                step: 64,
                                onEditingChanged: { isEditing in
                                    if !isEditing {
                                        localModelViewModel.applyMaxReasoningTokensDraft()
                                    }
                                }
                            )
                            .frame(width: 240)

                            Text("\(Int(localModelViewModel.maxReasoningTokensDraft)) tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsRow(
                        title: "Download",
                        subtitle: localModelViewModel.isDownloaded
                            ? "Downloaded"
                            : "Download the selected model from Hugging Face.",
                        systemImage: "arrow.down.circle"
                    ) {
                        HStack(spacing: 10) {
                            if localModelViewModel.isDownloaded {
                                Text("Ready")
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Download") {
                                    localModelViewModel.downloadSelectedModel()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(localModelViewModel.isDownloading)
                            }

                            if localModelViewModel.isDownloading {
                                ProgressView(value: localModelViewModel.downloadProgress)
                                    .frame(width: 120)
                            }
                        }
                    }

                    if let errorMessage = localModelViewModel.downloadErrorMessage {
                        SettingsRow(
                            title: "Download error",
                            subtitle: errorMessage,
                            systemImage: "exclamationmark.triangle"
                        ) {
                            EmptyView()
                        }
                    }
                }

                SettingsCard(
                    title: localized("settings.ai.openrouter_connection.title"),
                    subtitle: localized("settings.ai.openrouter_connection.subtitle")
                ) {
                    SettingsRow(
                        title: localized("settings.ai.api_key.title"),
                        subtitle: localized("settings.ai.api_key.subtitle"),
                        systemImage: "key.fill"
                    ) {
                        HStack(spacing: 8) {
                            SecureField(localized("settings.ai.api_key.placeholder"), text: $viewModel.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)

                            Button(localized("settings.ai.api_key.validate")) {
                                Task { await viewModel.validateKey() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    HStack(spacing: 12) {
                        SettingsStatusPill(status: viewModel.keyStatus)
                        Spacer()
                        Button(
                            showAdvanced
                                ? localized("settings.ai.advanced.hide")
                                : localized("settings.ai.advanced.show")
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAdvanced.toggle()
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if showAdvanced {
                        SettingsRow(
                            title: localized("settings.ai.base_url.title"),
                            subtitle: localized("settings.ai.base_url.subtitle"),
                            systemImage: "link"
                        ) {
                            TextField(localized("settings.ai.base_url.placeholder"), text: $viewModel.baseURL)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                        }
                    }
                }

                SettingsCard(
                    title: localized("settings.ai.model_selection.title"),
                    subtitle: localized("settings.ai.model_selection.subtitle")
                ) {
                    SettingsRow(
                        title: localized("settings.ai.model.title"),
                        subtitle: localized("settings.ai.model.subtitle"),
                        systemImage: "magnifyingglass"
                    ) {
                        HStack(spacing: 8) {
                            TextField(localized("settings.ai.model.placeholder"), text: $viewModel.modelQuery)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                                .onSubmit {
                                    viewModel.commitModelEntry()
                                    Task { await viewModel.validateModel() }
                                }
                                .onChange(of: viewModel.modelQuery) {
                                    Task { await viewModel.loadModels() }
                                }

                            Button(localized("settings.ai.model.test_latency")) {
                                Task { await viewModel.testModel() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if viewModel.shouldShowSuggestions() {
                        ModelSuggestionList(models: viewModel.filteredModels) { model in
                            viewModel.selectModel(model)
                            Task { await viewModel.validateModel() }
                        }
                    }

                    HStack(spacing: 12) {
                        SettingsStatusPill(status: viewModel.modelStatus)
                        SettingsStatusPill(status: viewModel.modelValidationStatus)
                        SettingsStatusPill(status: viewModel.testStatus)

                        Spacer()
                    }
                }

                SettingsCard(
                    title: localized("settings.ai.system_prompt.title"),
                    subtitle: localized("settings.ai.system_prompt.subtitle")
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(localized("settings.ai.system_prompt.help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $viewModel.systemPrompt)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                            )

                        HStack(spacing: 12) {
                            Button(localized("settings.ai.system_prompt.reset")) {
                                viewModel.systemPrompt = ""
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                        }
                    }
                }

                SettingsCard(
                    title: localized("settings.ai.reasoning_card.title"),
                    subtitle: localized("settings.ai.reasoning_card.subtitle")
                ) {
                    SettingsRow(
                        title: localized("settings.ai.reasoning.title"),
                        subtitle: localized("settings.ai.reasoning.subtitle"),
                        systemImage: "brain"
                    ) {
                        Toggle("", isOn: $viewModel.reasoningEnabled)
                            .toggleStyle(.switch)
                    }
                }

            }
            .padding(.top, 4)
            .onAppear {
                viewModel.loadApiKeyIfAvailable()
                Task { await viewModel.loadModels() }
            }
        }
    }
}
