import Foundation

actor OpenRouterAPIClient {
    struct RequestContext: Sendable {
        let baseURL: String
        let appName: String
        let referer: String
    }

    private struct Request: Sendable {
        let path: String
        let method: String
        let apiKey: String?
        let context: RequestContext
        let body: Data?
    }

    private struct OpenRouterModelResponse: Decodable {
        let data: [OpenRouterModel]
    }

    private let urlSession: URLSession

    init(urlSession: URLSession = URLSession(configuration: .default)) {
        self.urlSession = urlSession
    }

    func fetchModels(
        apiKey: String?,
        context: RequestContext
    ) async throws -> [OpenRouterModel] {
        let request = try makeRequest(Request(
            path: "models",
            method: "GET",
            apiKey: apiKey,
            context: context,
            body: nil
        ))

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
        context: RequestContext
    ) async throws {
        _ = try await fetchModels(
            apiKey: apiKey,
            context: context
        )
    }

    func testModel(
        apiKey: String,
        model: String,
        context: RequestContext
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
            context: context,
            body: body
        )
        return Date().timeIntervalSince(startTime)
    }

    func chatCompletion(
        apiKey: String,
        context: RequestContext,
        body: Data
    ) async throws -> Data {
        let request = try makeRequest(Request(
            path: "chat/completions",
            method: "POST",
            apiKey: apiKey,
            context: context,
            body: body
        ))

        let (data, response) = try await urlSession.data(for: request)
        let status = try httpStatus(from: response)
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw OpenRouterServiceError.serverError(status, body: body)
        }
        return data
    }

    /// Streaming chat completion using SSE (Server-Sent Events)
    func chatCompletionStreaming(
        apiKey: String,
        context: RequestContext,
        body: Data,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws {
        var request = try makeStreamingRequest(Request(
            path: "chat/completions",
            method: "POST",
            apiKey: apiKey,
            context: context,
            body: body
        ))

        // Set Accept header for SSE
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await urlSession.bytes(for: request)
        let status = try httpStatus(from: response)
        guard status == 200 else {
            // Read error body
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorBody = String(data: errorData, encoding: .utf8)
            throw OpenRouterServiceError.serverError(status, body: errorBody)
        }

        // Parse SSE stream line by line
        var buffer = ""
        for try await line in bytes.lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !trimmedLine.isEmpty else { continue }

            // SSE format: "data: {json}" or "data: [DONE]"
            if trimmedLine.hasPrefix("data: ") {
                let dataPart = String(trimmedLine.dropFirst(6))  // Remove "data: "

                if dataPart == "[DONE]" {
                    break
                }

                // Send chunk to callback
                onChunk(dataPart)
            }
        }
    }

    private func makeRequest(_ request: Request) throws -> URLRequest {
        guard let base = URL(string: request.context.baseURL) else { throw OpenRouterServiceError.invalidURL }
        let url = base.appendingPathComponent(request.path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        if let apiKey = request.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if !request.context.referer.isEmpty {
            urlRequest.setValue(request.context.referer, forHTTPHeaderField: "HTTP-Referer")
        }
        if !request.context.appName.isEmpty {
            urlRequest.setValue(request.context.appName, forHTTPHeaderField: "X-Title")
        }
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }

    private func makeStreamingRequest(_ request: Request) throws -> URLRequest {
        guard let base = URL(string: request.context.baseURL) else { throw OpenRouterServiceError.invalidURL }
        let url = base.appendingPathComponent(request.path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        if let apiKey = request.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if !request.context.referer.isEmpty {
            urlRequest.setValue(request.context.referer, forHTTPHeaderField: "HTTP-Referer")
        }
        if !request.context.appName.isEmpty {
            urlRequest.setValue(request.context.appName, forHTTPHeaderField: "X-Title")
        }
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        // Disable automatic decompression to get raw bytes for SSE parsing
        urlRequest.setValue("no-transform", forHTTPHeaderField: "Accept-Encoding")
        return urlRequest
    }

    private func httpStatus(from response: URLResponse) throws -> Int {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterServiceError.invalidResponse
        }
        return httpResponse.statusCode
    }
}
