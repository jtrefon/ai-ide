//
//  OpenRouterSettingsViewModel.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import SwiftUI

@MainActor
final class OpenRouterSettingsViewModel: ObservableObject {
    enum StatusKind {
        case idle
        case loading
        case success
        case warning
        case error
    }

    struct Status: Equatable {
        let kind: StatusKind
        let message: String
    }

    @Published var apiKey: String {
        didSet { persist() }
    }
    @Published var baseURL: String {
        didSet { persist() }
    }
    @Published var modelQuery: String {
        didSet { updateModelQuery() }
    }
    @Published var selectedModel: String {
        didSet { persist() }
    }
    @Published var systemPrompt: String {
        didSet { persist() }
    }
    @Published var reasoningEnabled: Bool {
        didSet { persist() }
    }

    @Published private(set) var models: [OpenRouterModel] = []
    @Published private(set) var filteredModels: [OpenRouterModel] = []
    @Published private(set) var modelStatus = Status(kind: .idle, message: "Models not loaded yet.")
    @Published private(set) var keyStatus = Status(kind: .idle, message: "Key not validated.")
    @Published private(set) var testStatus = Status(kind: .idle, message: "No test run.")
    @Published private(set) var modelValidationStatus = Status(kind: .idle, message: "Model not validated.")

    private let store: OpenRouterSettingsStore
    private let client: OpenRouterAPIClient
    private let appName = "OSX IDE"
    private let referer = ""
    private var hasLoadedModels = false

    init(
        store: OpenRouterSettingsStore = OpenRouterSettingsStore(),
        client: OpenRouterAPIClient = OpenRouterAPIClient()
    ) {
        let settings = store.load()
        self.store = store
        self.client = client
        self.apiKey = settings.apiKey
        self.baseURL = settings.baseURL
        self.selectedModel = settings.model
        self.modelQuery = settings.model
        self.systemPrompt = settings.systemPrompt
        self.reasoningEnabled = settings.reasoningEnabled
    }

    func loadModels(force: Bool = false) async {
        if hasLoadedModels && !force { return }
        modelStatus = Status(kind: .loading, message: "Loading models...")
        do {
            let models = try await client.fetchModels(
                apiKey: apiKey.isEmpty ? nil : apiKey,
                baseURL: baseURL,
                appName: appName,
                referer: referer
            )
            let sorted = models.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            self.models = sorted
            hasLoadedModels = true
            updateModelQuery()
            modelStatus = Status(kind: .success, message: "\(sorted.count) models available.")
        } catch {
            modelStatus = Status(kind: .error, message: error.localizedDescription)
        }
    }

    func validateKey() async {
        guard !apiKey.isEmpty else {
            keyStatus = Status(kind: .warning, message: "Add an API key to validate.")
            return
        }
        keyStatus = Status(kind: .loading, message: "Validating key...")
        do {
            try await client.validateKey(
                apiKey: apiKey,
                baseURL: baseURL,
                appName: appName,
                referer: referer
            )
            keyStatus = Status(kind: .success, message: "Key is valid.")
        } catch {
            keyStatus = Status(kind: .error, message: error.localizedDescription)
        }
    }

    func validateModel() async {
        let activeModel = activeModelId()
        guard !activeModel.isEmpty else {
            modelValidationStatus = Status(kind: .warning, message: "Select a model to validate.")
            return
        }
        modelValidationStatus = Status(kind: .loading, message: "Validating model...")
        if models.isEmpty {
            await loadModels(force: true)
        }
        if models.contains(where: { $0.id == activeModel }) {
            modelValidationStatus = Status(kind: .success, message: "Model found in OpenRouter list.")
        } else {
            modelValidationStatus = Status(kind: .error, message: "Model not found. Check spelling.")
        }
    }

    func testModel() async {
        guard !apiKey.isEmpty else {
            testStatus = Status(kind: .warning, message: "Add an API key to run a test.")
            return
        }
        let activeModel = activeModelId()
        guard !activeModel.isEmpty else {
            testStatus = Status(kind: .warning, message: "Select a model before testing.")
            return
        }
        testStatus = Status(kind: .loading, message: "Testing model latency...")
        do {
            let latency = try await client.testModel(
                apiKey: apiKey,
                model: activeModel,
                baseURL: baseURL,
                appName: appName,
                referer: referer
            )
            let ms = Int(latency * 1000)
            testStatus = Status(kind: .success, message: "Response in \(ms) ms.")
        } catch {
            testStatus = Status(kind: .error, message: error.localizedDescription)
        }
    }

    func commitModelEntry() {
        selectedModel = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func selectModel(_ model: OpenRouterModel) {
        modelQuery = model.id
        selectedModel = model.id
        modelValidationStatus = Status(kind: .idle, message: "Model selected.")
    }

    func shouldShowSuggestions() -> Bool {
        !filteredModels.isEmpty && !modelQuery.isEmpty
    }

    private func updateModelQuery() {
        let trimmed = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filteredModels = []
        } else {
            filteredModels = models.filter {
                $0.displayName.localizedCaseInsensitiveContains(trimmed) ||
                    $0.id.localizedCaseInsensitiveContains(trimmed)
            }
            filteredModels = Array(filteredModels.prefix(60))
        }
        persist()
    }

    private func persist() {
        let activeModel = activeModelId()
        let settings = OpenRouterSettings(
            apiKey: apiKey,
            model: activeModel,
            baseURL: baseURL,
            systemPrompt: systemPrompt,
            reasoningEnabled: reasoningEnabled
        )
        store.save(settings)
    }

    private func activeModelId() -> String {
        let candidate = selectedModel.isEmpty ? modelQuery : selectedModel
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
