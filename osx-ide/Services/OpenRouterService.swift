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
    
    static let empty = OpenRouterSettings(
        apiKey: "",
        model: "",
        baseURL: "https://openrouter.ai/api/v1",
        systemPrompt: ""
    )
}

final class OpenRouterSettingsStore {
    private let userDefaults = UserDefaults.standard
    private let apiKeyKey = "OpenRouterAPIKey"
    private let modelKey = "OpenRouterModel"
    private let baseURLKey = "OpenRouterBaseURL"
    private let systemPromptKey = "OpenRouterSystemPrompt"
    
    func load() -> OpenRouterSettings {
        OpenRouterSettings(
            apiKey: userDefaults.string(forKey: apiKeyKey) ?? "",
            model: userDefaults.string(forKey: modelKey) ?? "",
            baseURL: userDefaults.string(forKey: baseURLKey) ?? OpenRouterSettings.empty.baseURL,
            systemPrompt: userDefaults.string(forKey: systemPromptKey) ?? ""
        )
    }
    
    func save(_ settings: OpenRouterSettings) {
        userDefaults.set(settings.apiKey, forKey: apiKeyKey)
        userDefaults.set(settings.model, forKey: modelKey)
        userDefaults.set(settings.baseURL, forKey: baseURLKey)
        userDefaults.set(settings.systemPrompt, forKey: systemPromptKey)
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
    case serverError(Int)
    case missingAPIKey
    case emptyModel
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The OpenRouter URL is invalid."
        case .invalidResponse:
            return "OpenRouter returned an unexpected response."
        case .serverError(let code):
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
    
    init(urlSession: URLSession = .shared) {
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
        guard status == 200 else { throw OpenRouterServiceError.serverError(status) }
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
        guard status == 200 else { throw OpenRouterServiceError.serverError(status) }
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
