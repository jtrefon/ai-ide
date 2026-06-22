import Foundation
import WebKit

/// Manages a persistent WKWebView session for multi-step browsing.
/// @MainActor because WKWebView requires the main thread.
@MainActor
public final class WebSession: NSObject, WKNavigationDelegate {
    public let id: String
    public let createdAt: Date
    private let webView: WKWebView
    private var continuation: CheckedContinuation<String, Error>?
    private var currentURL: URL?

    public init(id: String) {
        self.id = id
        self.createdAt = Date()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    /// Load a URL and return page text.
    public func navigate(to url: URL, timeout: TimeInterval = 20) async throws -> String {
        currentURL = url
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: AppError.aiServiceError("WebSession deallocated"))
                return
            }
            self.continuation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: timeout))
        }
    }

    /// Click an element matching a CSS selector and return the new page text.
    public func click(selector: String, timeout: TimeInterval = 20) async throws -> String {
        // Inject click script
        let clickJS = """
        (function() {
            let el = document.querySelector('\(selector)');
            if (!el) return 'NO_ELEMENT';
            if (el.tagName === 'A') {
                let href = el.getAttribute('href');
                if (href) return 'NAVIGATE:' + href;
            }
            el.click();
            return 'CLICKED';
        })();
        """
        let result = try await evaluateJS(clickJS)

        if result.hasPrefix("NAVIGATE:"), let href = result.dropFirst(9).description.removingPercentEncoding, let url = URL(string: href, relativeTo: currentURL) {
            return try await navigate(to: url, timeout: timeout)
        }

        // Wait for page to settle after click
        try await Task.sleep(nanoseconds: 2_000_000_000)
        return try await getText()
    }

    /// Get all links on the current page.
    public func getLinks() async throws -> String {
        let js = """
        Array.from(document.querySelectorAll('a[href]')).map(function(a) {
            return JSON.stringify({
                text: (a.innerText || '').trim().substring(0, 80),
                href: a.getAttribute('href')
            });
        }).join('\\n');
        """
        let raw = try await evaluateJS(js)
        guard !raw.isEmpty else { return "No links found." }
        return raw
    }

    /// Get the current page text.
    public func getText() async throws -> String {
        return try await extractText()
    }

    /// Navigate back in history.
    public func goBack(timeout: TimeInterval = 20) async throws -> String {
        try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: AppError.aiServiceError("WebSession deallocated"))
                return
            }
            self.continuation = continuation
            webView.goBack()
        }
    }

    /// Navigate forward in history.
    public func goForward(timeout: TimeInterval = 20) async throws -> String {
        try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: AppError.aiServiceError("WebSession deallocated"))
                return
            }
            self.continuation = continuation
            webView.goForward()
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await fulfillWithPageText()
        }
    }

    nonisolated public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    // MARK: - Private

    private func fulfillWithPageText() {
        Task {
            let text = await extractText()
            continuation?.resume(returning: text)
            continuation = nil
        }
    }

    private func extractText() async -> String {
        let js = """
        (function() {
            function getText() {
                let results = document.querySelectorAll('.result, .result__body, [data-testid="result"], .g, .rc');
                if (results.length > 0) return Array.from(results).map(function(r) { return r.innerText; }).filter(Boolean).join('\\n---\\n');
                let article = document.querySelector('article');
                if (article) return article.innerText;
                let main = document.querySelector('main, [role="main"], #content, .content');
                if (main) return main.innerText;
                let body = document.body;
                if (!body) return '';
                for (let sel of ['script','style','nav','footer','header','aside','.ad','.ads','.sidebar','.menu','.nav','.social','.share']) {
                    document.querySelectorAll(sel).forEach(function(el) { if(el.parentNode) el.remove(); });
                }
                return body.innerText;
            }
            let text = getText() || '';
            text = text.replace(/\\s{3,}/g, '\\n\\n').trim();
            if (text.length < 50) return '(empty page)';
            return text.length > 50000 ? text.substring(0, 50000) + '\\n\\n... [truncated]' : text;
        })();
        """
        return await evaluateJS(js)
    }

    private func evaluateJS(_ js: String) async -> String {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(js) { result, _ in
                continuation.resume(returning: (result as? String) ?? "")
            }
        }
    }
}

/// Actor that manages active web browsing sessions.
public actor WebSessionStore {
    public static let shared = WebSessionStore()
    private var sessions: [String: WebSession] = [:]

    public func create() async -> String {
        let id = UUID().uuidString
        let session = await MainActor.run { WebSession(id: id) }
        sessions[id] = session
        return id
    }

    public func get(_ id: String) -> WebSession? {
        sessions[id]
    }

    public func close(_ id: String) {
        sessions.removeValue(forKey: id)
    }

    public func activeCount() -> Int {
        sessions.count
    }
}
