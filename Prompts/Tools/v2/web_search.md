# web_search Tool

## Purpose
Search the web using Google to find current information, documentation, tutorials, and external resources.

## When to Use
- Finding documentation for libraries, frameworks, or APIs
- Researching best practices, patterns, or solutions
- Looking up error messages or troubleshooting
- Finding tutorials or guides

## When NOT to Use
- Do NOT use for information already in the project codebase
- Do NOT use for simple lookups that read_file can handle

## Parameters
- **query** (required, string): The search query. Use natural language or keywords.

## Usage Examples
- `{ "query": "Swift 6 concurrency best practices 2026" }`
- `{ "query": "React TypeScript testing framework comparison" }`

## Output Structure
Returns a ToolFeedback envelope:
- **status**: "success"
- **content.items[]**: Search results with title, URL, and snippet
- **message**: "Found 10 results"

## Success Indicators
- content.items contains search results

## Best Practices
1. Be specific with queries for better results
2. Follow up with web_browse to read full articles from the results
3. Use current year in queries for up-to-date information
