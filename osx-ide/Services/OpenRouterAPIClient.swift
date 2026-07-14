import Foundation

/// Why this exists: `URLSession.bytes(for:)` + `bytes.lines` has **no** stream-level
/// deadline. If a server sends SSE keep-alive comments (`: ping`) but never delivers
/// `[DONE]`, the consumption loop hangs forever (the keep-alives keep the connection
/// "active" so `timeoutIntervalForRequest` never fires). This wrapper enforces two
/// independent, cancellable deadlines and fails the stream with `StreamLivenessError`
/// so the caller's retry/backoff path can recover instead of stalling indefinitely.
enum StreamLivenessError: Error {
    /// No *meaningful* (non-comment) SSE line received for longer than `idle`.
    case idle
    /// The whole stream exceeded `absolute` regardless of activity.
    case absolute
}

/// Tracks the last *meaningful* (non-comment) SSE line time so the concurrent
/// reader/watcher tasks can share it safely.
private actor LivenessClock {
    var last: ContinuousClock.Instant
    init(_ start: ContinuousClock.Instant) { self.last = start }
    func mark() { last = .now }
    func idleElapsed(now: ContinuousClock.Instant) -> Duration { last.duration(to: now) }
}

struct SSEStreamDeadline: Sendable {
    let idle: Duration
    let absolute: Duration
    let granularity: Duration

    /// Defaults are env-overridable (seconds) and fall back to safe production values.
    static func `default`() -> SSEStreamDeadline {
        let env = ProcessInfo.processInfo.environment
        let idleSec = env["OSXIDE_STREAM_IDLE_TIMEOUT_SEC"].flatMap(TimeInterval.init) ?? 120
        let absSec = env["OSXIDE_STREAM_ABSOLUTE_TIMEOUT_SEC"].flatMap(TimeInterval.init) ?? 600
        return SSEStreamDeadline(
            idle: .nanoseconds(Int((idleSec * 1_000_000_000).rounded())),
            absolute: .nanoseconds(Int((absSec * 1_000_000_000).rounded())),
            granularity: .nanoseconds(1_000_000_000)
        )
    }

    /// Returns an async throwing stream of the raw SSE lines from `bytes`. The stream
    /// fails with `StreamLivenessError` if either deadline is breached. SSE keep-alive
    /// comments (`:`) are treated as connection activity but do **not** reset the idle
    /// timer — only real `data:` lines count as meaningful progress.
    func lines(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let start = ContinuousClock.now
            let clock = LivenessClock(start)
            let reader = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                        if !line.trimmingCharacters(in: .newlines).hasPrefix(":") {
                            await clock.mark()
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let watcher = Task {
                while true {
                    try? await Task.sleep(for: granularity)
                    if Task.isCancelled { return }
                    let now = ContinuousClock.now
                    if start.duration(to: now) >= absolute {
                        continuation.finish(throwing: StreamLivenessError.absolute)
                        return
                    }
                    if await clock.idleElapsed(now: now) >= idle {
                        continuation.finish(throwing: StreamLivenessError.idle)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                watcher.cancel()
            }
        }
    }
}

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

    static func ssePayloads<S: Sequence>(from lines: S) -> [String] where S.Element == String {
        var payloads: [String] = []
        var eventDataLines: [String] = []

        func flushEvent() {
            guard !eventDataLines.isEmpty else { return }
            payloads.append(eventDataLines.joined(separator: "\n"))
            eventDataLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let rawLine = line.trimmingCharacters(in: .newlines)
            if rawLine.isEmpty {
                flushEvent()
                continue
            }
            if rawLine.hasPrefix(":") {
                continue
            }
            if rawLine.hasPrefix("data:") {
                var value = String(rawLine.dropFirst(5))
                if value.hasPrefix(" ") {
                    value.removeFirst()
                }
                eventDataLines.append(value)
            }
        }

        flushEvent()
        return payloads
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

    /// Non-streaming chat completion with transparent transport-level retry.
    ///
    /// Connection failures (TCP/TLS drops, offline, timeouts) and HTTP 200
    /// responses with an empty/truncated body are retried on a fresh connection
    /// before this method returns. HTTP error statuses (auth, rate-limit, 5xx)
    /// are semantic and surfaced immediately. The caller — and therefore the
    /// agent — only ever observes a valid payload or a definitive failure.
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

        let maxAttempts = TransportRetryConfig.maxAttempts
        var lastConnectionError: Error?

        for attempt in 0..<maxAttempts {
            do {
                let (data, response) = try await urlSession.data(for: request)
                let status = try httpStatus(from: response)
                guard status == 200 else {
                    let body = String(data: data, encoding: .utf8)
                    throw OpenRouterServiceError.serverError(status, body: body)
                }
                if !data.isEmpty {
                    return data
                }
                // HTTP 200 but no body: a dropped/truncated response at the
                // transport layer. Retry transparently.
                lastConnectionError = nil
            } catch {
                if !Self.isTransportRetryable(error) {
                    throw error
                }
                lastConnectionError = error
            }

            if attempt < maxAttempts - 1 {
                try await TransportRetryConfig.backoff(attempt: attempt)
            }
        }

        if let error = lastConnectionError {
            throw error
        }
        throw OpenRouterServiceError.invalidResponse
    }

    /// Streaming chat completion with transparent transport-level retry.
    ///
    /// A connection drop, stream stall, or an HTTP 200 stream that closes having
    /// delivered zero content is retried on a fresh connection — entirely below
    /// the agent. Once any real content has been delivered to `onChunk`, retries
    /// stop and the stream is left to the coordinator for resumption. If every
    /// attempt delivers zero content (a genuinely empty model response), this
    /// returns normally so the coordinator can apply its empty-response correction;
    /// if every attempt is a connection failure, the last error is thrown so the
    /// coordinator can show its network-offline banner.
    func chatCompletionStreaming(
        apiKey: String,
        context: RequestContext,
        body: Data,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws {
        let maxAttempts = TransportRetryConfig.maxAttempts
        var lastConnectionError: Error?

        for attempt in 0..<maxAttempts {
            do {
                let delivered = try await performStreamingAttempt(
                    apiKey: apiKey,
                    context: context,
                    body: body,
                    onChunk: onChunk
                )
                if delivered {
                    return
                }
                // Stream connected and closed but delivered no content: a
                // truncated/dropped response. Retry transparently.
                lastConnectionError = nil
            } catch let StreamAttemptError.retryable(underlying) {
                lastConnectionError = underlying
            } catch let StreamAttemptError.definitive(underlying) {
                throw underlying
            }

            if attempt < maxAttempts - 1 {
                try await TransportRetryConfig.backoff(attempt: attempt)
            }
        }

        if let error = lastConnectionError {
            throw error
        }
    }

    /// A single streaming attempt. Returns `true` if any content was delivered to
    /// `onChunk`. Connection/stall failures before content are surfaced as
    /// `StreamAttemptError.retryable`; semantic HTTP errors and stalls after
    /// content are `StreamAttemptError.definitive` (not retried here).
    private func performStreamingAttempt(
        apiKey: String,
        context: RequestContext,
        body: Data,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> Bool {
        var request = try makeStreamingRequest(Request(
            path: "chat/completions",
            method: "POST",
            apiKey: apiKey,
            context: context,
            body: body
        ))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let deadline = SSEStreamDeadline.default()

        do {
            let (bytes, response) = try await urlSession.bytes(for: request)
            let status = try httpStatus(from: response)
            guard status == 200 else {
                var errorData = Data()
                for try await byte in bytes {
                    errorData.append(byte)
                }
                let errorBody = String(data: errorData, encoding: .utf8)
                throw StreamAttemptError.definitive(
                    OpenRouterServiceError.serverError(status, body: errorBody))
            }

            var eventDataLines: [String] = []
            var deliveredContent = false

            func flushEvent() {
                guard !eventDataLines.isEmpty else { return }
                onChunk(eventDataLines.joined(separator: "\n"))
                deliveredContent = true
                eventDataLines.removeAll(keepingCapacity: true)
            }

            do {
                for try await line in deadline.lines(from: bytes) {
                    let rawLine = line.trimmingCharacters(in: .newlines)
                    if rawLine.isEmpty {
                        flushEvent()
                        continue
                    }
                    if rawLine.hasPrefix(":") {
                        continue
                    }
                    if rawLine.hasPrefix("data:") {
                        var dataPart = String(rawLine.dropFirst(5))
                        if dataPart.hasPrefix(" ") {
                            dataPart.removeFirst()
                        }
                        if dataPart == "[DONE]" {
                            flushEvent()
                            break
                        }
                        eventDataLines.append(dataPart)
                    }
                }
            } catch let error as StreamLivenessError {
                // A stall is a server/protocol-side issue: the connection is still
                // alive and ACKing SSE keep-alives, so it is not a transport drop.
                // Surface it definitively so the coordinator can resume — never
                // transparently retry, which would open a redundant connection to a
                // stuck server (and defeat the stall-detection harness test).
                throw StreamAttemptError.definitive(
                    OpenRouterServiceError.streamTimeout(error))
            } catch {
                throw deliveredContent
                    ? StreamAttemptError.definitive(error)
                    : StreamAttemptError.retryable(error)
            }

            flushEvent()
            return deliveredContent
        } catch let sae as StreamAttemptError {
            throw sae
        } catch {
            // urlSession.bytes(for:) threw before any content: a transport drop.
            throw StreamAttemptError.retryable(error)
        }
    }

    /// Distinguishes a transport failure we may transparently retry (`retryable`,
    /// no content delivered yet) from a definitive failure that must propagate to
    /// the coordinator (`definitive`).
    private enum StreamAttemptError: Error {
        case retryable(Error)
        case definitive(Error)
    }

    /// Transparent transport-retry policy. Connection drops, stalls, and
    /// empty/truncated bodies are retried on a fresh connection with escalating
    /// backoff. Configurable via environment for debugging/tests.
    private enum TransportRetryConfig {
        static var maxAttempts: Int {
            Int(ProcessInfo.processInfo.environment["OSXIDE_TRANSPORT_RETRY_ATTEMPTS"] ?? "") ?? 4
        }

        static var baseDelay: TimeInterval {
            TimeInterval(ProcessInfo.processInfo.environment["OSXIDE_TRANSPORT_RETRY_BASE_SEC"] ?? "") ?? 0.5
        }

        static var maxDelay: TimeInterval {
            TimeInterval(ProcessInfo.processInfo.environment["OSXIDE_TRANSPORT_RETRY_MAX_SEC"] ?? "") ?? 8.0
        }

        static func backoff(attempt: Int) async throws {
            let delay = min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private static func isTransportRetryable(_ error: Error) -> Bool {
        if let server = error as? OpenRouterServiceError {
            switch server {
            case .serverError, .invalidResponse, .invalidURL, .missingAPIKey, .emptyModel:
                return false
            case .streamTimeout:
                return true
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .resourceUnavailable, .dataNotAllowed, .internationalRoamingOff,
                 .callIsActive, .secureConnectionFailed,
                 .backgroundSessionWasDisconnected:
                return true
            default:
                return false
            }
        }
        return false
    }

    func fetchKiloBalance(
        apiKey: String,
        apiBaseURL: String
    ) async throws -> Decimal? {
        guard let base = URL(string: apiBaseURL) else {
            throw OpenRouterServiceError.invalidURL
        }
        let url = base.appendingPathComponent("api/profile/balance")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await urlSession.data(for: request)
        let status = try httpStatus(from: response)
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw OpenRouterServiceError.serverError(status, body: body)
        }

        struct BalanceResponse: Decodable {
            let balance: Decimal?
        }

        return try JSONDecoder().decode(BalanceResponse.self, from: data).balance
    }

    func fetchDeepSeekBalance(
        apiKey: String,
        apiBaseURL: String
    ) async throws -> Decimal? {
        guard let base = URL(string: apiBaseURL) else {
            throw OpenRouterServiceError.invalidURL
        }
        let url = base.appendingPathComponent("user/balance")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        let status = try httpStatus(from: response)
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw OpenRouterServiceError.serverError(status, body: body)
        }

        struct DeepSeekBalanceResponse: Decodable {
            struct BalanceInfo: Decodable {
                let currency: String?
                let totalBalance: String?
                let grantedBalance: String?
                let toppedUpBalance: String?
                
                enum CodingKeys: String, CodingKey {
                    case currency
                    case totalBalance = "total_balance"
                    case grantedBalance = "granted_balance"
                    case toppedUpBalance = "topped_up_balance"
                }
            }
            let isAvailable: Bool?
            let balanceInfos: [BalanceInfo]?
            
            enum CodingKeys: String, CodingKey {
                case isAvailable = "is_available"
                case balanceInfos = "balance_infos"
            }
        }

        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        // Return total balance in USD from first balance info
        if let balanceStr = decoded.balanceInfos?.first?.totalBalance {
            return Decimal(string: balanceStr)
        }
        return nil
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
