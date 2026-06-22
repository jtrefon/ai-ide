import Foundation
import WebKit

/// Manages a hidden WKWebView for page rendering and text extraction.
/// Runs on @MainActor because WKWebView requires the main thread.
@MainActor
final class WebViewEngine: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var continuation: CheckedContinuation<String, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    /// Load a URL and return the rendered text content.
    /// Waits for the page to fully render (including JS-loaded content),
    /// then extracts clean text via JavaScript.
    func extractText(from url: URL, timeout: TimeInterval = 20) async throws -> String {
        let request = URLRequest(url: url, timeoutInterval: timeout)
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: AppError.aiServiceError("WebViewEngine deallocated"))
                return
            }
            self.continuation = continuation
            webView.load(request)
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Wait for page to settle and JS content to load, then extract text
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await extractPageText()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private func extractPageText() {
        let js = """
        (function() {
            function getText() {
                // Try common search result containers
                let results = document.querySelectorAll('.result, .result__body, .result__snippet, [data-testid="result"], .g, .rc, .web-result');
                if (results.length > 0) {
                    return Array.from(results).map(r => r.innerText).filter(Boolean).join('\\n---\\n');
                }

                // Try article or main content for non-search pages
                let article = document.querySelector('article');
                if (article) return article.innerText;

                let main = document.querySelector('main, [role="main"], #content, .content');
                if (main) return main.innerText;

                // Fallback: body with cleanup
                let body = document.body;
                if (!body) return '';

                for (let sel of ['script', 'style', 'nav', 'footer', 'header', 'aside',
                                 '.ad', '.ads', '[class*="ad"]', '[id*="ad"]',
                                 '.sidebar', '.menu', '.nav', '.social', '.share']) {
                    for (let el of document.querySelectorAll(sel)) {
                        if (el.parentNode) el.remove();
                    }
                }
                return body.innerText;
            }

            let text = getText() || '';
            text = text.replace(/\\s{3,}/g, '\\n\\n').trim();
            let maxLen = 50000;
            if (text.length > maxLen) {
                text = text.substring(0, maxLen) + '\\n\\n... [truncated]';
            }
            if (text.length < 50) return '(empty page)';
            return text;
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self else { return }
            if let text = result as? String, !text.isEmpty {
                self.continuation?.resume(returning: text)
            } else {
                self.continuation?.resume(returning: "(empty page)")
            }
            self.continuation = nil
        }
    }
}
