import Foundation
import WebKit

/// Manages a persistent WKWebView session for multi-step browsing.
/// SPA-aware: uses MutationObserver + WKScriptMessageHandler to detect
/// when JavaScript-rendered content is actually ready, not just didFinish.
@MainActor
public final class WebSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
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

        // Message handler for SPA content-ready signal
        let userContent = WKUserContentController()
        config.userContentController = userContent

        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        userContent.add(self, name: "contentReady")
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "contentReady")
    }

    /// Navigate to a URL and return the rendered page text.
    /// Waits for the SPA to signal content readiness, not just didFinish.
    public func navigate(to url: URL, timeout: TimeInterval = 25) async throws -> String {
        currentURL = url
        return try await navigateWithContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: AppError.aiServiceError("WebSession deallocated"))
                return
            }
            self.continuation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: timeout))
        }
    }

    /// Click the first element matching a CSS selector and return the new page text.
    public func click(selector: String, timeout: TimeInterval = 25) async throws -> String {
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
        if result.hasPrefix("NAVIGATE:"), 
           let href = String(result.dropFirst(9)).removingPercentEncoding,
           let url = URL(string: href, relativeTo: currentURL) {
            return try await navigate(to: url, timeout: timeout)
        }
        // Wait for the click to settle and inject watcher
        return try await navigateWithContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: AppError.aiServiceError("WebSession deallocated"))
                return
            }
            self.continuation = continuation
            // The watcher will catch the mutation
            injectContentWatcher()
        }
    }

    /// Get all links on the current page as JSON.
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
        return raw.isEmpty ? "No links found." : raw
    }

    /// Get current page text without re-navigating.
    public func getText() async throws -> String {
        return try await evaluateJS("document.body?.innerText || '(empty page)'")
    }

    /// Navigate back in history.
    public func goBack() async throws -> String {
        return try await navigateWithContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: AppError.aiServiceError("WebSession deallocated"))
                return
            }
            self.continuation = continuation
            webView.goBack()
        }
    }

    /// Navigate forward in history.
    public func goForward() async throws -> String {
        return try await navigateWithContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: AppError.aiServiceError("WebSession deallocated"))
                return
            }
            self.continuation = continuation
            webView.goForward()
        }
    }

    // MARK: - Private Helpers

    private func navigateWithContinuation(_ setup: (CheckedContinuation<String, Error>) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            setup(continuation)
        }
    }

    private func evaluateJS(_ js: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(js) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (result as? String) ?? "")
                }
            }
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // didFinish fires when the initial HTML loads, but SPAs are just starting.
            // Inject the SPA watcher that signals when actual content is rendered.
            injectContentWatcher()
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
            // For SPAs, provisional navigation failures (e.g., resource timeouts)
            // are often recoverable. Only fail if we have no content at all.
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    // MARK: - WKScriptMessageHandler

    nonisolated public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "contentReady" else { return }
        Task { @MainActor in
            let text = (message.body as? String) ?? ""
            continuation?.resume(returning: text.isEmpty ? "(empty page)" : text)
            continuation = nil
        }
    }

    // MARK: - Content Watcher JS

    private func injectContentWatcher() {
        let js = """
        (function() {
            if (window.__contentWatchInjected) return;
            window.__contentWatchInjected = true;
            var maxWait = 20000; // 20s total
            var start = Date.now();

            function signal(text) {
                try {
                    window.webkit.messageHandlers.contentReady.postMessage(text);
                } catch(e) {}
            }

            function getContent() {
                // DuckDuckGo: search results (filter out skeleton/whitespace-only elements)
                var results = document.querySelectorAll('.result, .result__body, .result__snippet, [data-testid="result"]');
                var texts = Array.from(results).map(function(r) { return r.innerText.trim(); }).filter(function(t) { return t.length > 0; });
                if (texts.length > 0) return texts.join('\\n\\n---\\n\\n');
                // Generic: article or main content
                var article = document.querySelector('article');
                if (article && article.innerText.trim().length > 200) return article.innerText;
                var main = document.querySelector('main, [role="main"], #content, .content');
                if (main && main.innerText.trim().length > 200) return main.innerText;
                // Body fallback (with cleanup)
                var body = document.body;
                if (!body) return null;
                ['script','style','nav','footer','header','aside'].forEach(function(sel) {
                    document.querySelectorAll(sel).forEach(function(el) {
                        if(el.parentNode) el.remove();
                    });
                });
                var text = body.innerText.trim();
                if (text.length > 500) return text;
                return null;
            }

            // Check immediately
            var content = getContent();
            if (content) { signal(content); return; }

            // Watch for DOM changes (SPA rendering)
            var observer = new MutationObserver(function() {
                var content = getContent();
                if (content) {
                    observer.disconnect();
                    signal(content);
                }
            });
            observer.observe(document.body || document.documentElement, {
                childList: true, subtree: true, attributes: false, characterData: true
            });

            // Timeout safety net
            setTimeout(function() {
                observer.disconnect();
                var content = getContent();
                signal(content || '(empty page)');
            }, maxWait);
        })();
        """

        webView.evaluateJavaScript(js) { _, _ in }
    }
}

/// WKScriptMessageHandler must be a class — use a thin wrapper that
/// forwards to the main WebSession via a weak reference.
private class DefaultScriptMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Forwarded via the session's own handler
    }
}

/// Actor that manages active web browsing sessions.
public actor WebSessionStore {
    public static let shared = WebSessionStore()
    private var sessions: [String: WebSession] = [:]

    public func create(sessionId: String = UUID().uuidString) async -> String {
        let session = await MainActor.run { WebSession(id: sessionId) }
        sessions[sessionId] = session
        return sessionId
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
