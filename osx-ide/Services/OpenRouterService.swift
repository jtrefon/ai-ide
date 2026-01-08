//
//  OpenRouterService.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Foundation

struct OpenRouterSettings: Equatable {
    var apiKey: String
    var model: String
    var baseURL: String
    var systemPrompt: String
    var reasoningEnabled: Bool
    
    static let empty = OpenRouterSettings(
        apiKey: "",
        model: "",
        baseURL: "https://openrouter.ai/api/v1",
        systemPrompt: "",
        reasoningEnabled: true
    )
}

final class OpenRouterSettingsStore {
    private let settingsStore = SettingsStore(userDefaults: .standard)
    private let apiKeyKey = "OpenRouterAPIKey"
    private let modelKey = "OpenRouterModel"
    private let baseURLKey = "OpenRouterBaseURL"
    private let systemPromptKey = "OpenRouterSystemPrompt"
    private let reasoningEnabledKey = "OpenRouterReasoningEnabled"
    
    func load() -> OpenRouterSettings {
        OpenRouterSettings(
            apiKey: settingsStore.string(forKey: apiKeyKey) ?? "",
            model: settingsStore.string(forKey: modelKey) ?? "",
            baseURL: settingsStore.string(forKey: baseURLKey) ?? OpenRouterSettings.empty.baseURL,
            systemPrompt: settingsStore.string(forKey: systemPromptKey) ?? "",
            reasoningEnabled: settingsStore.bool(forKey: reasoningEnabledKey, default: true)
        )
    }
    
    func save(_ settings: OpenRouterSettings) {
        settingsStore.set(settings.apiKey, forKey: apiKeyKey)
        settingsStore.set(settings.model, forKey: modelKey)
        settingsStore.set(settings.baseURL, forKey: baseURLKey)
        settingsStore.set(settings.systemPrompt, forKey: systemPromptKey)
        settingsStore.set(settings.reasoningEnabled, forKey: reasoningEnabledKey)
    }
}

struct OpenRouterModel: Identifiable, Decodable, Hashable {
    let id: String
    let name: String?
    
    var displayName: String {
        name ?? id
    }
}

private struct OpenRouterModelResponse: Decodable {
    let data: [OpenRouterModel]
}

enum OpenRouterServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int, body: String?)
    case missingAPIKey
    case emptyModel
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The OpenRouter URL is invalid."
        case .invalidResponse:
            return "OpenRouter returned an unexpected response."
        case .serverError(let code, let body):
            if let body, !body.isEmpty {
                return "OpenRouter request failed (HTTP \(code)): \(body)"
            }
            return "OpenRouter request failed (HTTP \(code))."
        case .missingAPIKey:
            return "An API key is required."
        case .emptyModel:
            return "Select a model before testing."
        }
    }
}

actor OpenRouterAPIClient {
    private let urlSession: URLSession
    
    init(urlSession: URLSession = URLSession(configuration: .default)) {
        self.urlSession = urlSession
    }
    
    func fetchModels(
        apiKey: String?,
        baseURL: String,
        appName: String,
        referer: String
    ) async throws -> [OpenRouterModel] {
        let request = try makeRequest(
            path: "models",
            method: "GET",
            apiKey: apiKey,
            baseURL: baseURL,
            appName: appName,
            referer: referer,
            body: nil
        )
        
        let (data, response) = try await urlSession.data(for: request)
        let status = try httpStatus(from: response)
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw OpenRouterServiceError.serverError(status, body: body)
        }
        let decoded = try JSONDecoder().decode(OpenRouterModelResponse.self, from: data)
        return decoded.data
    }
    
    func validateKey(
        apiKey: String,
        baseURL: String,
        appName: String,
        referer: String
    ) async throws {
        _ = try await fetchModels(
            apiKey: apiKey,
            baseURL: baseURL,
            appName: appName,
            referer: referer
        )
    }
    
    func testModel(
        apiKey: String,
        model: String,
        baseURL: String,
        appName: String,
        referer: String
    ) async throws -> TimeInterval {
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "Ping for latency check. Reply with pong."]
            ],
            "max_tokens": 16,
            "temperature": 0.0
        ]
        
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let startTime = Date()
        _ = try await chatCompletion(
            apiKey: apiKey,
            baseURL: baseURL,
            appName: appName,
            referer: referer,
            body: body
        )
        return Date().timeIntervalSince(startTime)
    }
    
    func chatCompletion(
        apiKey: String,
        baseURL: String,
        appName: String,
        referer: String,
        body: Data
    ) async throws -> Data {
        let request = try makeRequest(
            path: "chat/completions",
            method: "POST",
            apiKey: apiKey,
            baseURL: baseURL,
            appName: appName,
            referer: referer,
            body: body
        )
        
        let (data, response) = try await urlSession.data(for: request)
        let status = try httpStatus(from: response)
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw OpenRouterServiceError.serverError(status, body: body)
        }
        return data
    }
    
    private func makeRequest(
        path: String,
        method: String,
        apiKey: String?,
        baseURL: String,
        appName: String,
        referer: String,
        body: Data?
    ) throws -> URLRequest {
        guard let base = URL(string: baseURL) else { throw OpenRouterServiceError.invalidURL }
        let url = base.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
        }
        if !appName.isEmpty {
            request.setValue(appName, forHTTPHeaderField: "X-Title")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    
    private func httpStatus(from response: URLResponse) throws -> Int {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterServiceError.invalidResponse
        }
        return httpResponse.statusCode
    }
}
