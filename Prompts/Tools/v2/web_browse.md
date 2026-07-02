# Tool: web_browse

WHAT: Fetches a URL and returns the page title, URL, and cleaned readable text content (strips ads, navigation, and clutter).

WHEN: Use AFTER web_search to read full articles, documentation pages, API references, or tutorials. Essential for getting complete information that snippets don't provide.

HOW:
- url (required, string): The full URL to browse, including https://.
- Overloading: Use the URLs returned by web_search results. For documentation, browse the specific version or section page.

OUTPUT: Returns the page title, URL, and main body text as plain text.
