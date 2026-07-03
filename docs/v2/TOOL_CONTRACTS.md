# Tool Contracts

This document defines the exact interface contracts for each tool. These contracts are used for both the old `AITool` protocol and the new `ToolDefinition` system.

---

## `search_code` — Code Navigation

### Intent

The sole tool for finding code by name, kind, or content. No ML, no semantic search. Pure structural lookup against the symbol index and FTS5.

### Parameters

```json
{
  "name": "search_code",
  "description": "Find code by name, kind, or content. The primary tool for code navigation — use this for ALL code discovery needs.",
  "parameters": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "Search term: class name, function name, variable name, file name, or text pattern. Case-insensitive partial match."
      },
      "kind": {
        "type": "string",
        "description": "Optional: filter by symbol kind. Values: 'class', 'struct', 'enum', 'protocol', 'function', 'method', 'variable', 'extension', 'typealias'. If omitted, searches all kinds.",
        "enum": ["class", "struct", "enum", "protocol", "function", "method", "variable", "extension", "typealias"]
      },
      "path": {
        "type": "string",
        "description": "Optional: scope search to a subdirectory (e.g. 'Services/', 'Sources/App'). Relative to project root."
      },
      "max_results": {
        "type": "integer",
        "description": "Maximum results to return. Default 30, max 100.",
        "default": 30
      }
    },
    "required": ["query"]
  }
}
```

### Return Value

```json
{
  "results": [
    {
      "file": "Sources/App/Services/DataManager.swift",
      "line": 42,
      "column": 1,
      "kind": "class",
      "name": "DataManager",
      "signature": "final class DataManager: ObservableObject",
      "context": "snippet of surrounding code (first 200 chars)"
    }
  ],
  "total": 1,
  "timed_out": false,
  "cache_hit": false
}
```

### Example Calls

```
# Find a class by name
search_code(query: "DataManager", kind: "class")
→ Found 1 result: DataManager.swift:42

# Find all functions matching "load"
search_code(query: "load", kind: "function")
→ Found 12 results ...

# Find files referencing "NetworkService" (text search, no kind filter)
search_code(query: "NetworkService")
→ Found 24 results ...

# Scope search to a subdirectory
search_code(query: "DatabaseManager", path: "Services/Index/")
→ Found 3 results ...
```

### Error Handling

| Condition | Response |
|-----------|----------|
| Missing `query` | "Error: 'query' parameter is required." |
| No results | "No matches found for 'query'." |
| Index not ready | "The code index is still building. Please wait a moment and try again." |
| Invalid `kind` | Ignore kind filter, search all kinds. |

---

## `project_context` — Project Knowledge Retrieval

### Intent

Retrieve persistent project knowledge: architecture, decisions, bug fixes, skills, and conversation summaries. This is the agent's long-term memory.

### Parameters

```json
{
  "name": "project_context",
  "description": "Retrieve project knowledge: architecture, past decisions, bug fixes, skills, and conversation summaries. Use this when you need to understand the project's context or recall what was previously learned.",
  "parameters": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "What to look up. Examples: 'architecture', 'how do we handle auth', 'networking pattern', 'build system'. Natural language queries work."
      },
      "max_results": {
        "type": "integer",
        "description": "Maximum context items to return. Default 5, max 20.",
        "default": 5
      }
    },
    "required": ["query"]
  }
}
```

### Return Value

```json
{
  "context": [
    {
      "type": "project_info",
      "key": "architecture",
      "value": "MVVM with service layer. Views observe ViewModels which call Services."
    },
    {
      "type": "memory",
      "category": "decision",
      "content": "We chose SQLite over CoreData for cross-platform compatibility.",
      "importance": 0.8
    },
    {
      "type": "chat_summary",
      "summary": "Fixed ghost commit bug by enabling SQLite WAL mode.",
      "files_touched": ["Services/Index/Database/DatabaseManager.swift"]
    }
  ],
  "total": 3,
  "confidence": 0.85
}
```

### Example Calls

```
# Ask about architecture
project_context(query: "architecture")
→ "PROJECT ARCHITECTURE: MVVM with service layer..."

# Ask about past decisions
project_context(query: "why did we choose SQLite")
→ "DECISION: We chose SQLite over CoreData for cross-platform compatibility."

# No context found
project_context(query: "payment processing")
→ "No relevant context found. You can teach me with the 'remember' tool."
```

### Error Handling

| Condition | Response |
|-----------|----------|
| No context found | "No relevant project context found. You can teach me with the 'remember' tool." |
| Memory database empty | "Project memory is empty. Context will accumulate as you work." |

---

## `remember` — Store Knowledge

### Intent

Explicitly store a piece of project knowledge or a discovered pattern. Used by both the LLM (via tool call) and the system (auto-generated).

### Parameters

```json
{
  "name": "remember",
  "description": "Store a piece of project knowledge for future reference. Use this when you discover a pattern, convention, architecture decision, or bug fix that should be remembered.",
  "parameters": {
    "type": "object",
    "properties": {
      "content": {
        "type": "string",
        "description": "The knowledge to remember. Be specific and concise. Example: 'All network calls go through NetworkService.shared'. Example: 'When adding a new screen: create View, ViewModel, and register in AppCoordinator'."
      },
      "category": {
        "type": "string",
        "description": "Category of knowledge.",
        "enum": ["architecture", "decision", "bugfix", "skill", "note"]
      },
      "importance": {
        "type": "number",
        "description": "Importance from 0.0 (trivial) to 1.0 (critical). Default 0.5.",
        "default": 0.5
      }
    },
    "required": ["content", "category"]
  }
}
```

### Return Value

```json
{
  "status": "remembered",
  "id": "mem_abc123",
  "category": "architecture",
  "importance": 0.7
}
```

### Example Calls

```
# Manual: LLM stores a discovered pattern
remember(content: "All view models conform to BaseViewModel protocol which handles error state", category: "architecture")
→ "Remembered. I'll recall this when relevant."

# Manual: Store a bug fix pattern
remember(content: "If SQLite shows inconsistent state, enable WAL mode: PRAGMA journal_mode=WAL", category: "bugfix", importance: 0.9)
→ "Remembered. I'll recall this when relevant."

# Auto: System stores a key decision from chat summary
# (Not called by LLM, triggered by ConversationSummarizer)
```

### Error Handling

| Condition | Response |
|-----------|----------|
| Empty content | "Error: 'content' is required." |
| Invalid category | "Error: category must be one of: architecture, decision, bugfix, skill, note." |

---

## Tool Registration (Removals)

### Remove from LLM's available tools

These tools are **replaced** by `search_code` and should be removed from the LLM's tool list:

| Tool Name | Replaced By | Reason |
|-----------|-------------|--------|
| `search_project` | `search_code` | Unified into single tool |
| `find_file` | `search_code` | Unified into single tool |
| `grep` | `search_code` | Unified into single tool |
| `find` (LocalFindTool) | `search_code` | Unified into single tool |
| `index_search_text` | `search_code` | Unified into single tool |
| `index_search_symbols` | `search_code` | Unified into single tool |
| `index_find_files` | `search_code` | Unified into single tool |
| `index_list_files` | `search_code` | Unified into single tool |
| `index_read_file` | `read_file` | Keep existing read_file tool |
| `get_project_structure` | (keep) | Keep as separate non-search tool |
| `index_list_memories` | `project_context` | Replaced by memory system |
| `index_add_memory` | `remember` | Replaced by memory system |

### Keep untouched

| Tool | Reason |
|------|--------|
| `read_file` | Independent, not search |
| `write_file` | Independent, not search |
| `replace_in_file` | Independent, not search |
| `delete_file` | Independent, not search |
| `list_files` | Independent, not search |
| `run_command` | Independent, not search |
| `web_search` | Independent, not search |
| `web_browse` | Independent, not search |
| `plan` | Independent, not search |
