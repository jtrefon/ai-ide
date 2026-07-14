## search — Understand an existing codebase: symbols, text, filenames (indexed / semantic / RAG)

**When to use:** The FIRST tool whenever you need to understand code that already exists — before you change it. Use it to map the project's structure, find where a function/class/variable is defined or used, and locate files by content or name. It combines semantic (vector) search, symbol lookup, the full-text index, and filesystem grep, and is the fastest way to discover "what is already here" before refactoring, migrating, or extending.

**Parameters:**
- query (required, string): The code, symbol, or text to search for.
- max_results (optional, integer): Max results (default 20, max 100).

**Expected output:** Plain text. A header `Found N occurrence(s) of "<query>":` followed by matches grouped by file (each file under a `# <path>` line), with the line number (`L<line>`), a bracketed match type (e.g. `[reference]`, `[filename]`), and the matching line content.
Example:
```
Found 3 occurrence(s) of "useState":

# src/App.tsx
  L12 [reference] const [count, setCount] = useState(0)
  L20 [reference] useState(saved)

# src/hooks.ts
  L4 [reference] export function useState<T>(...)
```
Read the matches directly from the text. There is no nested JSON `content.items` field.

**Common situations & recovery:**
- Before a refactor/migration: search the project first to enumerate every file and symbol you will touch.
- No results: Try a broader query, or part of the name.
