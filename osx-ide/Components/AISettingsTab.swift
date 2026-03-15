//
//  AISettingsTab.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import SwiftUI

struct AISettingsTab: View {
    @ObservedObject var openRouterViewModel: OpenRouterSettingsViewModel
    @ObservedObject var alibabaViewModel: OpenRouterSettingsViewModel
    @ObservedObject var kiloCodeViewModel: OpenRouterSettingsViewModel
    @ObservedObject var providerSelectionViewModel: AIProviderSelectionViewModel
    @ObservedObject var localModelViewModel: LocalModelSettingsViewModel
    @ObservedObject var embeddingModelViewModel: EmbeddingModelSettingsViewModel
    @State private var showAdvanced = false

    private var activeViewModel: OpenRouterSettingsViewModel {
        switch providerSelectionViewModel.selectedProvider {
        case .openRouter:
            return openRouterViewModel
        case .alibabaCloud:
            return alibabaViewModel
        case .kiloCode:
            return kiloCodeViewModel
        }
    }

    private var remoteProviderViewModels: [OpenRouterSettingsViewModel] {
        [
            openRouterViewModel,
            alibabaViewModel,
            kiloCodeViewModel
        ]
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<OpenRouterSettingsViewModel, Value>) -> Binding<Value> {
        Binding(
            get: { self.activeViewModel[keyPath: keyPath] },
            set: { self.activeViewModel[keyPath: keyPath] = $0 }
        )
    }

    private var reasoningCardSubtitle: String {
        switch providerSelectionViewModel.selectedProvider {
        case .kiloCode:
            return "Choose how much reasoning Kilo Code uses: none, model-only, agent-only, or both."
        case .openRouter, .alibabaCloud:
            return localized("settings.ai.reasoning_card.subtitle")
        }
    }

    private var reasoningRowSubtitle: String {
        switch providerSelectionViewModel.selectedProvider {
        case .kiloCode:
            return "None disables thinking, Model uses internal-only thinking, Agent uses app-side reasoning, and Model + Agent enables both."
        case .openRouter, .alibabaCloud:
            return localized("settings.ai.reasoning.subtitle")
        }
    }

    var body: some View {
        let viewModel = activeViewModel
        let localize = localized

        return ScrollView {
            VStack(spacing: 20) {
                ProviderSelectionSection(selectedProvider: $providerSelectionViewModel.selectedProvider)
                ProviderConnectionSection(
                    localize: localize,
                    apiKey: binding(\.apiKey),
                    baseURL: binding(\.baseURL),
                    showAdvanced: $showAdvanced,
                    keyStatus: viewModel.keyStatus,
                    validateKey: {
                        Task { await viewModel.validateKey() }
                    }
                )
                ModelSelectionSection(
                    localize: localize,
                    modelQuery: binding(\.modelQuery),
                    viewModel: viewModel,
                    onCommit: {
                        viewModel.commitModelEntry()
                        Task { await viewModel.validateModel() }
                    },
                    onSearchChange: {
                        Task { await viewModel.loadModels() }
                    },
                    onTest: {
                        Task { await viewModel.testModel() }
                    },
                    onSuggestionTap: { model in
                        viewModel.selectModel(model)
                        Task { await viewModel.validateModel() }
                    }
                )
                SystemPromptSection(
                    localize: localize,
                    systemPrompt: binding(\.systemPrompt),
                    onReset: { viewModel.systemPrompt = "" }
                )
                ReasoningSection(
                    localize: localize,
                    subtitle: reasoningCardSubtitle,
                    rowSubtitle: reasoningRowSubtitle,
                    reasoningMode: binding(\.reasoningMode),
                    toolPromptMode: binding(\.toolPromptMode),
                    ragDuringToolLoop: binding(\.ragEnabledDuringToolLoop)
                )
                SettingsCard(
                    title: "Local Models",
                    subtitle: "Download and manage local/offline model artifacts."
                ) {
                    LocalModelSettingsView(viewModel: localModelViewModel)
                }
                SettingsCard(
                    title: "Embedding Models",
                    subtitle: "Download models for semantic search in the codebase index."
                ) {
                    EmbeddingModelSettingsView(viewModel: embeddingModelViewModel)
                }
            }
            .padding(.top, 4)
        }
        .onAppear {
            remoteProviderViewModels.forEach { $0.loadApiKeyIfAvailable() }
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for viewModel in remoteProviderViewModels {
                        group.addTask {
                            await viewModel.loadModels()
                        }
                    }
                }
            }
        }
    }

}

private struct ProviderSelectionSection: View {
    @Binding var selectedProvider: RemoteAIProvider

    var body: some View {
        SettingsCard(
            title: "Provider",
            subtitle: "Choose the primary online provider for chat and agent runs."
        ) {
            Picker("Provider", selection: $selectedProvider) {
                ForEach(RemoteAIProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 240)
        }
    }
}

private struct ProviderConnectionSection: View {
    let localize: (String) -> String
    @Binding var apiKey: String
    @Binding var baseURL: String
    @Binding var showAdvanced: Bool
    let keyStatus: OpenRouterSettingsViewModel.Status
    let validateKey: () -> Void

    var body: some View {
        SettingsCard(
            title: localize("settings.ai.openrouter_connection.title"),
            subtitle: localize("settings.ai.openrouter_connection.subtitle")
        ) {
            SettingsRow(
                title: localize("settings.ai.api_key.title"),
                subtitle: localize("settings.ai.api_key.subtitle"),
                systemImage: "key.fill"
            ) {
                HStack(spacing: 8) {
                    SecureField(localize("settings.ai.api_key.placeholder"), text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)

                    Button(localize("settings.ai.api_key.validate")) {
                        validateKey()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack(spacing: 12) {
                SettingsStatusPill(status: keyStatus)
                Spacer()
                Button(
                    showAdvanced
                        ? localize("settings.ai.advanced.hide")
                        : localize("settings.ai.advanced.show")
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAdvanced.toggle()
                    }
                }
                .buttonStyle(.bordered)
            }

            if showAdvanced {
                SettingsRow(
                    title: localize("settings.ai.base_url.title"),
                    subtitle: localize("settings.ai.base_url.subtitle"),
                    systemImage: "link"
                ) {
                    TextField(localize("settings.ai.base_url.placeholder"), text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
            }
        }
    }
}

private struct ModelSelectionSection: View {
    let localize: (String) -> String
    @Binding var modelQuery: String
    @ObservedObject var viewModel: OpenRouterSettingsViewModel
    let onCommit: () -> Void
    let onSearchChange: () -> Void
    let onTest: () -> Void
    let onSuggestionTap: (OpenRouterModel) -> Void

    var body: some View {
        SettingsCard(
            title: localize("settings.ai.model_selection.title"),
            subtitle: localize("settings.ai.model_selection.subtitle")
        ) {
            SettingsRow(
                title: localize("settings.ai.model.title"),
                subtitle: localize("settings.ai.model.subtitle"),
                systemImage: "magnifyingglass"
            ) {
                HStack(spacing: 8) {
                    TextField(localize("settings.ai.model.placeholder"), text: $modelQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .onSubmit(onCommit)
                        .onChange(of: modelQuery) { _ in
                            onSearchChange()
                        }

                    Button(localize("settings.ai.model.test_latency")) {
                        onTest()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.shouldShowSuggestions() {
                ModelSuggestionList(models: viewModel.filteredModels) { model in
                    onSuggestionTap(model)
                }
            }

            HStack(spacing: 12) {
                SettingsStatusPill(status: viewModel.modelStatus)
                SettingsStatusPill(status: viewModel.modelValidationStatus)
                SettingsStatusPill(status: viewModel.testStatus)
                Spacer()
            }
        }
    }
}

private struct SystemPromptSection: View {
    let localize: (String) -> String
    @Binding var systemPrompt: String
    let onReset: () -> Void

    var body: some View {
        SettingsCard(
            title: localize("settings.ai.system_prompt.title"),
            subtitle: localize("settings.ai.system_prompt.subtitle")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localize("settings.ai.system_prompt.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $systemPrompt)
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
                    Button(localize("settings.ai.system_prompt.reset")) {
                        onReset()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }
}

private struct ReasoningSection: View {
    let localize: (String) -> String
    let subtitle: String
    let rowSubtitle: String
    @Binding var reasoningMode: ReasoningMode
    @Binding var toolPromptMode: ToolPromptMode
    @Binding var ragDuringToolLoop: Bool

    var body: some View {
        SettingsCard(
            title: localize("settings.ai.reasoning_card.title"),
            subtitle: subtitle
        ) {
            SettingsRow(
                title: localize("settings.ai.reasoning.title"),
                subtitle: rowSubtitle,
                systemImage: "brain"
            ) {
                Picker("", selection: $reasoningMode) {
                    Text("None").tag(ReasoningMode.none)
                    Text("Model").tag(ReasoningMode.model)
                    Text("Agent").tag(ReasoningMode.agent)
                    Text("Model + Agent").tag(ReasoningMode.modelAndAgent)
                }
                .pickerStyle(.segmented)
                .frame(width: 340)
            }

            SettingsRow(
                title: "Tool prompt mode",
                subtitle: "Choose the instruction style used when tools are enabled.",
                systemImage: "text.quote"
            ) {
                Picker("", selection: $toolPromptMode) {
                    Text("Full static").tag(ToolPromptMode.fullStatic)
                    Text("Concise").tag(ToolPromptMode.concise)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            SettingsRow(
                title: "RAG during tool loop",
                subtitle: "When disabled, tool-loop turns skip RAG retrieval and use explicit context only.",
                systemImage: "rectangle.stack.badge.magnifyingglass"
            ) {
                Toggle("", isOn: $ragDuringToolLoop)
                    .toggleStyle(.switch)
            }
        }
    }
}
