# web_browse Tool

## Purpose

Fetch a URL and extract the page's title and main readable text content (strips ads, navigation, and clutter).

## When to Use

- AFTER web_search to read full articles, documentation, or API references
- Reading detailed guides or tutorials
- Checking API documentation for specific parameters or endpoints

## When NOT to Use

- Do NOT use for search — use web_search instead
- Do NOT use for pages behind login walls or paywalls

## Parameters

- **url** (required, string): The full URL to browse, including https://.

## Usage Examples

- `{ "url": "https://developer.apple.com/documentation/swift/concurrency" }`
- `{ "url": "https://react.dev/learn/typescript" }`

## Output Structure

Returns a ToolFeedback envelope:

- **status**: "success" | "error"
- **content.text**: The page title and main body text
- **message**: URL and content length

## Success Indicators

- content.text contains readable page content

## Error Handling

- NETWORK_ERROR: URL unreachable. Check the URL or try again.
- BLOCKED: Site may be blocking automated access. Try a different source.

## Best Practices

1. Always use URLs from web_search results
2. Browse specific documentation pages, not search results pages
