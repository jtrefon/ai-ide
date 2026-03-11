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
        }
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

    var body: some View {
        let viewModel = activeViewModel

        return ScrollView {
            VStack(spacing: 20) {
                providerSelectionCard
                connectionCard
                modelSelectionCard(viewModel: viewModel)
                systemPromptCard(viewModel: viewModel)
                reasoningCard
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
            openRouterViewModel.loadApiKeyIfAvailable()
            alibabaViewModel.loadApiKeyIfAvailable()
            Task {
                async let _ = openRouterViewModel.loadModels()
                async let _ = alibabaViewModel.loadModels()
                _ = await ((), ())
            }
        }
    }

    private var providerSelectionCard: some View {
        SettingsCard(
            title: "Provider",
            subtitle: "Choose the primary online provider for chat and agent runs."
        ) {
            Picker("Provider", selection: $providerSelectionViewModel.selectedProvider) {
                ForEach(RemoteAIProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
        }
    }

    private var connectionCard: some View {
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
                    SecureField(localized("settings.ai.api_key.placeholder"), text: binding(\.apiKey))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)

                    Button(localized("settings.ai.api_key.validate")) {
                        Task { await activeViewModel.validateKey() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack(spacing: 12) {
                SettingsStatusPill(status: activeViewModel.keyStatus)
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
                    TextField(localized("settings.ai.base_url.placeholder"), text: binding(\.baseURL))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
            }
        }
    }

    private func modelSelectionCard(viewModel: OpenRouterSettingsViewModel) -> some View {
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
                    TextField(localized("settings.ai.model.placeholder"), text: binding(\.modelQuery))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .onSubmit {
                            viewModel.commitModelEntry()
                            Task { await viewModel.validateModel() }
                        }
                        .onChange(of: viewModel.modelQuery) { _ in
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
    }

    private func systemPromptCard(viewModel: OpenRouterSettingsViewModel) -> some View {
        SettingsCard(
            title: localized("settings.ai.system_prompt.title"),
            subtitle: localized("settings.ai.system_prompt.subtitle")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localized("settings.ai.system_prompt.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: binding(\.systemPrompt))
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
    }

    private var reasoningCard: some View {
        SettingsCard(
            title: localized("settings.ai.reasoning_card.title"),
            subtitle: localized("settings.ai.reasoning_card.subtitle")
        ) {
            SettingsRow(
                title: localized("settings.ai.reasoning.title"),
                subtitle: localized("settings.ai.reasoning.subtitle"),
                systemImage: "brain"
            ) {
                Picker("", selection: binding(\.reasoningMode)) {
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
                Picker("", selection: binding(\.toolPromptMode)) {
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
                Toggle("", isOn: binding(\.ragEnabledDuringToolLoop))
                    .toggleStyle(.switch)
            }
        }
    }

}
