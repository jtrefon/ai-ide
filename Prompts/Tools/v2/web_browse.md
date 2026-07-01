# web_browse Tool

## Purpose
Read full web pages with a persistent browser session. Supports full JavaScript rendering, clicking links, and multi-step navigation. Use this to read documentation, tutorials, and full articles when web_search snippets are insufficient.

## Parameters
- **action** (optional, string): Action to perform:
  - `open` (default): Navigate to a URL and read the page content.
  - `read`: Re-read the current page content.
  - `click`: Click an element by CSS selector.
  - `links`: List clickable links on the current page.
  - `go_back`: Navigate back in history.
  - `go_forward`: Navigate forward in history.
  - `reload`: Reload the current page.
  - `close`: Close the browsing session.
- **url** (optional, string): URL to navigate to. Required for `action: open`.
- **session_id** (optional, string): Existing session ID for multi-step navigation. Required for actions other than `open`.
- **selector** (optional, string): CSS selector for `action: click` (e.g., `a.nav-link`, `#submit-btn`).
- **max_chars** (optional, integer): Maximum characters to return (default 10,000, max 50,000).

## Workflow

1. Start: `web_browse(action: "open", url: "https://example.com")` → returns page content + session_id
2. Explore: `web_browse(action: "click", selector: "a.docs-link", session_id: "...")` → follows the link
3. Read: `web_browse(action: "read", session_id: "...")` → re-read current page
4. Done: `web_browse(action: "close", session_id: "...")` → clean up

## Feedback Format

```
status: success
message: "Opened page (12,450 chars)"
content:
  data:
    text: |
      # Swift Concurrency
      
      Swift provides built-in support for writing asynchronous...
      ...
  metadata:
    url: "https://developer.apple.com/documentation/swift/concurrency"
    sessionId: "abc-123"
    charCount: "12450"
```

## Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| `NETWORK_TIMEOUT` | Page load timed out | Retry with simpler page or check URL |
| `NAVIGATION_FAILED` | Could not navigate to URL | Check URL spelling |
| `SESSION_NOT_FOUND` | Invalid session ID | Start a new session with action: open |
| `SELECTOR_NOT_FOUND` | CSS selector didn't match any element | Check the selector or use `links` to find valid selectors |

## Best Practices

1. **Session reuse**: Use session_id to continue browsing. Reusing a session keeps cookies, history, and JS context.
2. **Check max_chars**: Large pages are truncated. Increase max_chars if you need more content.
3. **Click navigation**: Use action: links to see what's clickable, then action: click to navigate.
4. **Read after click**: After clicking a link, use action: read to get the new page content.
5. **Close sessions**: Close sessions when done to free browser resources.
