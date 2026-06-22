import Foundation

/// Web search and URL browsing tool.
/// Uses Safari's WebKit engine with full JavaScript support.
/// Extracts clean text content using Reader-mode-style extraction.
struct WebSearchTool: AITool {
    let name = "web_search"
    let description = "Search the web or browse any URL. Uses Safari's WebKit engine with full JavaScript " +
        "support. Extracts clean article text (no ads, no navigation, no sidebars). " +
        "Provide either a search query or a direct URL."

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
                    "description": "Direct URL to browse (e.g. https://example.com/page). Uses Reader mode text extraction."
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
        let maxChars = min(50000, max(1000, raw["max_chars"] as? Int ?? 10000))

        guard query != nil || urlString != nil else {
            return "Provide a 'query' for web search or a 'url' to browse a specific page."
        }

        let targetURL: URL
        if let urlString {
            guard let url = URL(string: urlString) else {
                return "Invalid URL: \(urlString)"
            }
            targetURL = url
        } else {
            let encoded = query!.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query!
            guard let url = URL(string: "https://duckduckgo.com/?q=\(encoded)") else {
                return "Failed to build search URL."
            }
            targetURL = url
        }

        // WKWebView must run on the main actor
        let text = try await fetchText(url: targetURL)

        guard !text.isEmpty else {
            return "No content retrieved from \(targetURL.absoluteString)."
        }

        let trimmed = text.count > maxChars
            ? String(text.prefix(maxChars)) + "\n\n... [truncated to \(maxChars) chars]"
            : text

        return """
        Source: \(targetURL.absoluteString)
        Content length: \(text.count) characters

        \(trimmed)
        """
    }

    @MainActor
    private func fetchText(url: URL) async throws -> String {
        let engine = WebViewEngine()
        return try await engine.extractText(from: url)
    }
}
