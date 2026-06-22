import Foundation

/// Web search and browsing tool with persistent session support.
/// Uses Safari's WebKit engine with full JavaScript execution.
struct WebSearchTool: AITool {
    let name = "web_search"
    let description = "Search the web and browse web pages. Uses Safari's WebKit engine with full JavaScript. " +
        "Supports multi-step navigation: search, click links, go back/forward. " +
        "Start with a query or URL, then use session_id to navigate further."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Search query. Performs a web search via DuckDuckGo."
                ],
                "url": [
                    "type": "string",
                    "description": "URL to navigate to directly."
                ],
                "session_id": [
                    "type": "string",
                    "description": "Existing session ID for multi-step navigation."
                ],
                "action": [
                    "type": "string",
                    "description": "Navigation action: text (default), click, links, back, forward, close."
                ],
                "selector": [
                    "type": "string",
                    "description": "CSS selector for action=click (e.g. 'a.result__link')."
                ],
                "max_chars": [
                    "type": "integer",
                    "description": "Maximum characters to return (default 10000, max 50000)."
                ]
            ],
            "required": []
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        let query = raw["query"] as? String
        let urlString = raw["url"] as? String
        let sessionID = raw["session_id"] as? String
        let action = (raw["action"] as? String)?.lowercased() ?? "text"
        let selector = raw["selector"] as? String
        let maxChars = min(50000, max(1000, raw["max_chars"] as? Int ?? 10000))

        if let sessionID {
            return try await performSessionAction(
                sessionID: sessionID, action: action, selector: selector, maxChars: maxChars
            )
        }

        // New session: build target URL
        let targetURL: URL
        if let urlString {
            guard let url = URL(string: urlString) else { return "Invalid URL: \(urlString)" }
            targetURL = url
        } else if let query {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            guard let url = URL(string: "https://duckduckgo.com/?q=\(encoded)") else {
                return "Failed to build search URL."
            }
            targetURL = url
        } else {
            return "Provide 'query' for search, 'url' to browse, or 'session_id' to continue."
        }

        let newSessionID = await WebSessionStore.shared.create()
        let text = await performNavigation(sessionID: newSessionID, url: targetURL)
        return trimAndFormat(text: text, maxChars: maxChars, sessionID: newSessionID)
    }

    @MainActor
    private func performNavigation(sessionID: String, url: URL) async -> String {
        guard let session = await WebSessionStore.shared.get(sessionID) else {
            return "Failed to create web session."
        }
        return (try? await session.navigate(to: url)) ?? "(navigation failed)"
    }

    @MainActor
    private func performSessionAction(sessionID: String, action: String, selector: String?, maxChars: Int) async -> String {
        guard let session = await WebSessionStore.shared.get(sessionID) else {
            return "Session '\(sessionID)' not found."
        }

        let text: String
        switch action {
        case "click":
            guard let selector else { return "Missing 'selector' for action=click." }
            text = (try? await session.click(selector: selector)) ?? "(click failed)"
        case "links":
            text = (try? await session.getLinks()) ?? "(get links failed)"
        case "back":
            text = (try? await session.goBack()) ?? "(go back failed)"
        case "forward":
            text = (try? await session.goForward()) ?? "(go forward failed)"
        case "close":
            await WebSessionStore.shared.close(sessionID)
            return "Session \(sessionID) closed."
        default:
            text = (try? await session.getText()) ?? "(get text failed)"
        }

        return trimAndFormat(text: text, maxChars: maxChars, sessionID: sessionID)
    }

    @MainActor
    private func navigateAndReturn(session: WebSession, to url: URL, maxChars: Int, sessionID: String) async -> String {
        let text = (try? await session.navigate(to: url)) ?? "(navigation failed)"
        return trimAndFormat(text: text, maxChars: maxChars, sessionID: sessionID)
    }

    private func trimAndFormat(text: String, maxChars: Int, sessionID: String) -> String {
        guard text != "(empty page)" else { return "(empty page)" }
        let trimmed = text.count > maxChars
            ? String(text.prefix(maxChars)) + "\n\n... [truncated]"
            : text
        return "Session: \(sessionID) | \(text.count) chars\n\n\(trimmed)"
    }
}
