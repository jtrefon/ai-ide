# web_search Tool

## Purpose
Search the web using Google. Returns structured search results with titles, URLs, and snippets. For reading full pages, use web_browse with a URL from the results.

## Parameters
- **query** (required, string): Search query.
- **max_results** (optional, integer): Maximum number of results to return (default 10, max 20).

## Feedback Format

```
status: success
message: "Found 10 results for 'Swift concurrency best practices'"
content:
  data:
    items:
      - label: "Swift Concurrency - Apple Documentation"
        kind: "result"
        description: "Learn about Swift concurrency with async/await, actors, and task groups."
        path: "https://developer.apple.com/documentation/swift/concurrency"
      - label: "Swift Concurrency Recipes"
        kind: "result"
        description: "Practical recipes for common concurrency patterns."
        path: "https://example.com/swift-concurrency-recipes"
  metadata:
    totalResults: "10"
    queryTimeMs: "850"
```

## Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| `SEARCH_BLOCKED` | Search engine blocked request (CAPTCHA) | Try a different query, or use web_browse with a known URL |
| `NETWORK_TIMEOUT` | Search timed out | Retry with simpler query |
| `NO_RESULTS` | No results found | Try different search terms |

## Best Practices

1. **Search first, browse second**: Use web_search to find relevant pages, then web_browse to read them in detail.
2. **Be specific**: Include language/framework names in queries for better results.
3. **Multiple queries**: If the first query doesn't find what you need, try different terms.
4. **Documentation**: For API documentation, include "documentation" or "docs" in your query.
