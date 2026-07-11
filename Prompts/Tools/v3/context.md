## context — Retrieve prior conversation context from the knowledge store

**When to use:** After context has been trimmed (you'll see a notice). When you need to recall prior findings, decisions, or code patterns from earlier in this session or previous sessions.

**Parameters:**
- query (required, string): What you need to recall. Be specific about the topic, file, or decision.
- max_results (optional, integer): Max results to return (1-10, default 5).

**Expected output:** Ranked snippets from prior work with source references and timestamps.
status: success
content.items: [{text, source, timestamp, relevance}, ...]
message: "Found N relevant results"

**Recovery:**
- No results: Try a different query — use more specific terms or keywords from the prior work.
