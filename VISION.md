# osx-ide: Mission, Vision & Principles

## Mission

Build the world's most responsive and private code editor by leveraging Apple Silicon to run AI on-device, without sacrificing the power of cloud models for complex work.

## Vision

osx-ide is the editor where AI adapts to the task — instant and invisible for daily coding, deeply capable when you need it. A 4B model on your Mac handles every keystroke, every quick question, every completion in <100ms. When you need to refactor across 50 files or build a feature from scratch, cloud models take over with best-in-class orchestration. All in one editor. All seamless. Your code never leaves your machine until you choose to reach for the cloud.

## Core Principles

### 1. Two pipelines, one editor
Local and cloud are completely separate AI pipelines that share an editor. They NEVER blend responsibilities. The local model does no orchestration. The cloud model never runs inline completion. Each is optimized for what it does best.

### 2. Speed is the feature, not a trade-off
Local interactions complete in <100ms. Cloud interactions complete in seconds, not minutes. If a feature adds latency without proportional value, it doesn't belong.

### 3. The small model does what it does well, nothing more
The 4B model is for: code completion, single-file Q&A, semantic search, diagnostics, quick transforms. It is NOT for: multi-file agentic coding, complex planning, tool orchestration. Forcing it to be something it was not is the source of most bloat in this codebase.

### 4. Every feature must prove its value or be removed
No "this might be useful someday" code. If a feature isn't actively used and valued by real users, it gets cut. The 4B target gives us a hard constraint that prevents scope creep.

### 5. Deep Mac integration, not cross-platform compromise
We win by being the best editor on macOS — native feel, Apple Silicon optimization, Metal acceleration, Shortcuts, Spotlight, Continuity. Not by being a mediocre editor everywhere.

## Target User

The professional macOS developer who wants AI that's always available, always fast, and always private. They work on a 16GB M4 MacBook Pro. They want daily AI assistance that doesn't require "sign in to continue" or "thinking for 30 seconds." They want cloud-scale AI power when they need it — on their terms.

## Competitive Positioning

| Dimension | Cursor | Windsurf | Codium/CodeLLM | osx-ide |
|---|---|---|---|---|
| Inline completion latency | ~500-2000ms (cloud) | ~500-2000ms (cloud) | ~500-2000ms (cloud) | **<100ms (local)** |
| Daily AI (completion, Q&A, explain) | Cloud, requires internet | Cloud, requires internet | Cloud, requires internet | **100% offline, instant** |
| Agentic coding | Excellent | Excellent | Good | **Target: excellent (cloud)** |
| Privacy | None (all cloud) | None (all cloud) | None (all cloud) | **Local: 100% on-device. Cloud: opt-in.** |
| Cost | $20/mo+ | $15/mo+ | Free tier limited | **Local: free. Cloud: usage-based.** |
| Mac integration | Electron | Electron | Electron | **Native SwiftUI + AppKit** |
| Offline capability | No | No | Limited | **Full offline mode** |

## The Two Pipelines

```
┌─────────────────────────────────────────────────────┐
│                    THE EDITOR                        │
│  NSTextView · Syntax Highlighting · Terminal         │
│  File Tree · Settings · Project State                │
├──────────────────────────┬──────────────────────────┤
│   LOCAL PIPELINE (4B)   │   CLOUD PIPELINE          │
│   Always on, <100ms     │   On demand, full power   │
├──────────────────────────┼──────────────────────────┤
│ Code completion          │ Agentic coding           │
│ Inline Q&A               │ Multi-file refactoring   │
│ Semantic search          │ Complex planning         │
│ Diagnostics explain      │ Tool orchestration       │
│ Quick transforms         │ RAG context injection    │
│ NO orchestration         │ Planner/Worker/QA graph  │
│ NO tool loop             │ Full tool loop + QA      │
│ Direct LLM call only     │ Iterative execution      │
├──────────────────────────┴──────────────────────────┤
│              SHARED INFRASTRUCTURE                    │
│  CodebaseIndex · Tool Implementations · File System  │
│  Terminal API · EventBus · CommandRegistry · DI      │
└─────────────────────────────────────────────────────┘
```

## What Success Looks Like

**v1.0** — Inline completion faster and more context-aware than any cloud editor. Inline AI popover for instant file-level Q&A. Semantic search that finds what you need in milliseconds. All offline, all private. Cloud pipeline matches Cursor's agentic capability.

**v1.5** — Experience engine learns from your patterns. Deeper Mac integration. Cloud pipeline exceeds Cursor in orchestration quality and reliability.

**v2.0** — The standard for what a native AI IDE should be. Local pipeline is indispensable. Cloud pipeline is best-in-class. Users choose osx-ide not despite it being Mac-only, but because of it.
