//
//  AISettingsTab.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import SwiftUI

struct AISettingsTab: View {
    @ObservedObject var viewModel: OpenRouterSettingsViewModel
    @State private var showAdvanced = false

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
                Task { await viewModel.loadModels() }
            }
        }
    }
}
