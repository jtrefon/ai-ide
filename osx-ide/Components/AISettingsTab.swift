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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard(
                    title: "OpenRouter Connection",
                    subtitle: "Store your API key and connection details."
                ) {
                    SettingsRow(
                        title: "API key",
                        subtitle: "Stored locally for this device.",
                        systemImage: "key.fill"
                    ) {
                        HStack(spacing: 8) {
                            SecureField("sk-or-...", text: $viewModel.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)
                            
                            Button("Validate") {
                                Task { await viewModel.validateKey() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        SettingsStatusPill(status: viewModel.keyStatus)
                        Spacer()
                        Button(showAdvanced ? "Hide Advanced" : "Show Advanced") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAdvanced.toggle()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if showAdvanced {
                        SettingsRow(
                            title: "Base URL",
                            subtitle: "Defaults to the OpenRouter API endpoint.",
                            systemImage: "link"
                        ) {
                            TextField("https://openrouter.ai/api/v1", text: $viewModel.baseURL)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                        }
                    }
                }
                
                SettingsCard(
                    title: "Model Selection",
                    subtitle: "Search OpenRouter models with autocomplete."
                ) {
                    SettingsRow(
                        title: "Model",
                        subtitle: "Type to search and select.",
                        systemImage: "magnifyingglass"
                    ) {
                        HStack(spacing: 8) {
                            TextField("e.g. openai/gpt-4o-mini", text: $viewModel.modelQuery)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                                .onSubmit {
                                    viewModel.commitModelEntry()
                                    Task { await viewModel.validateModel() }
                                }
                                .onChange(of: viewModel.modelQuery) {
                                    Task { await viewModel.loadModels() }
                                }
                            
                            Button("Test Latency") {
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
                    title: "System Prompt",
                    subtitle: "Override the default system instructions."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Use this to steer tone, formatting, and coding style.")
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
                            Button("Reset Prompt") {
                                viewModel.systemPrompt = ""
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                        }
                    }
                }

                SettingsCard(
                    title: "Reasoning",
                    subtitle: "Show the assistant's multi-step reasoning panel in chat."
                ) {
                    SettingsRow(
                        title: "Reasoning",
                        subtitle: "Adds an expandable reasoning section above assistant responses.",
                        systemImage: "brain"
                    ) {
                        Toggle("", isOn: $viewModel.reasoningEnabled)
                            .toggleStyle(.switch)
                    }
                }

                LanguageModulesSection()
            }
            .padding(.top, 4)
            .onAppear {
                Task { await viewModel.loadModels() }
            }
        }
    }
}

struct LanguageModulesSection: View {
    @ObservedObject var moduleManager = LanguageModuleManager.shared
    
    var body: some View {
        SettingsCard(
            title: "Language Modules",
            subtitle: "Enable or disable language-specific features for better performance."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(moduleManager.availableLanguages, id: \.self) { language in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(language.rawValue.capitalized)
                                .font(.headline)
                            Text("Syntax coloring, symbol extraction, and IntelliSense.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { moduleManager.isEnabled(language) },
                            set: { enabled in moduleManager.toggleModule(language, enabled: enabled) }
                        ))
                        .toggleStyle(.switch)
                    }
                    
                    if language != moduleManager.availableLanguages.last {
                        Divider()
                            .opacity(0.1)
                    }
                }
            }
        }
    }
}
