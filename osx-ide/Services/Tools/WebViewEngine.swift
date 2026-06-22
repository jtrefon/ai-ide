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
        let pref = WKPreferences()
        pref.setValue(true, forKey: "fullScreenEnabled")
        config.preferences = pref
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        #if DEBUG
        // Allow http (not just https) for local testing
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        #endif
    }

    /// Load a URL and return the rendered text content.
    /// Uses JavaScript to extract the main article text after the page loads.
    func extractText(from url: URL, timeout: TimeInterval = 15) async throws -> String {
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

    /// Load HTML string directly (for search results processing).
    func extractText(fromHTML html: String, baseURL: URL, timeout: TimeInterval = 10) async throws -> String {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: AppError.aiServiceError("WebViewEngine deallocated"))
                return
            }
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
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
            // Try Safari Reader mode via readability algorithm
            function getReadableText() {
                // Check for article tag
                let article = document.querySelector('article');
                if (article) return article.innerText;

                // Check for main content areas
                let main = document.querySelector('main, [role="main"], #content, .content, .post, .article');
                if (main) return main.innerText;

                // Fallback: body text with some cleanup
                let body = document.body;
                if (!body) return '';

                // Remove scripts, styles, navs, footers, ads
                for (let sel of ['script', 'style', 'nav', 'footer', 'header', 'aside',
                                 '.ad', '.ads', '.advertisement', '.sidebar', '.menu',
                                 '.nav', '.footer', '.header', '.social', '.share',
                                 '.comments', '.comment', '#comments', '#footer', '#header']) {
                    for (let el of document.querySelectorAll(sel)) {
                        if (el.parentNode) el.remove();
                    }
                }

                return body.innerText;
            }

            let text = getReadableText();
            // Clean up excessive whitespace
            text = text.replace(/\\s{3,}/g, '\\n\\n');
            text = text.trim();
            // Truncate to avoid huge responses
            let maxLen = 50000;
            if (text.length > maxLen) {
                text = text.substring(0, maxLen) + '\\n\\n... [truncated]';
            }
            return text;
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self else { return }
            if let text = result as? String, !text.isEmpty {
                self.continuation?.resume(returning: text)
            } else if let error {
                // Fallback: try simpler extraction
                self.webView.evaluateJavaScript("document.body?.innerText ?? ''") { result2, _ in
                    if let text2 = result2 as? String, !text2.isEmpty {
                        self.continuation?.resume(returning: text2)
                    } else {
                        self.continuation?.resume(returning: "(empty page)")
                    }
                }
            } else {
                self.continuation?.resume(returning: "(empty page)")
            }
            self.continuation = nil
        }
    }
}
