export const SITE_TITLE = "Compass | Native AI IDE for macOS";
export const SITE_DESCRIPTION =
  "A Swift-native AI IDE for developers who want local speed, private context, and serious agentic coding without giving up control.";

export const BASE_URL = "/ai-ide";
export const REPO = "https://github.com/jtrefon/ai-ide";
export const RELEASES = `${REPO}/releases`;

/** Replace this with your Formspree form ID (or other static-form backend URL) */
export const BETA_FORM_ACTION = "https://formspree.io/f/";

export const NAV = [
  { label: "Tech", href: "/tech" },
  { label: "Beta", href: "/beta" },
  { label: "Contributors", href: "/contributors" },
  { label: "Investors", href: "/investors" },
] as const;

export const SOCIAL = {
  github: REPO,
} as const;

export const LATEST_MACOS = "macOS 26 (Apple Silicon)";
export const REMOTE_PROVIDERS =
  "OpenRouter, Alibaba Cloud, Kilo Code, DeepSeek, and any OpenAI-compatible endpoint";

export const FEATURES_SHIPPING = [
  { title: "On-device FIM autocomplete", desc: `<100ms ghost-text completion via local model, tuned for cancellation and compact prompts.` },
  { title: "Native local inference", desc: `MLX-backed models supporting offline chat, local quick actions, configurable context length and quantised KV cache.` },
  { title: "Codebase intelligence", desc: `SQLite FTS5 index tracking files, symbols, chunks, and HNSW-backed embedding retrieval for grounded answers.` },
  { title: "Provider choice", desc: `Route heavy work through any provider - OpenRouter, Alibaba Cloud, DeepSeek, Kilo Code, or your own local model.` },
  { title: "Inline AI popover", desc: `Cursor-anchored Q&A panel for instant explain, refactor, or ask - without switching context.` },
  { title: "Semantic search", desc: `HNSW ANN vector index with CoreML embeddings, 10-50x faster than brute-force with ~95-99% recall.` },
] as const;

export const FEATURES_BETA = [
  { title: "Agentic tool execution", desc: `Orchestration graph (Planner > Worker > QA > Final) with 20+ tools, stall detection, and recovery.` },
  { title: "Multi-file refactoring", desc: `Autonomous execution of complex multi-file changes with diff-preview and checkpoint rollback.` },
  { title: "Remote sessions", desc: `SSH and SFTP integration so the agent works in your infrastructure.` },
  { title: "Project memory", desc: `Adaptive rules and inspectable memories that teach the assistant your conventions per-repository.` },
] as const;

export const PIPELINE_LOCAL = [
  { feature: "Latency", value: "<100 ms" },
  { feature: "Model", value: "On-device LLM via MLX" },
  { feature: "Privacy", value: "100% offline, no data leaves your machine" },
  { feature: "Tasks", value: "FIM completion, inline Q&A, semantic search, quick transforms" },
  { feature: "Network", value: "No internet required" },
];

export const PIPELINE_CLOUD = [
  { feature: "Latency", value: "5-30 s (task-dependent)" },
  { feature: "Model", value: "Any provider via OpenRouter or direct API" },
  { feature: "Privacy", value: "Opt-in; you choose when code is sent" },
  { feature: "Tasks", value: "Agentic refactors, multi-file planning, tool orchestration, review" },
  { feature: "Network", value: "Requires internet, full offline fallback" },
];

export const COMPETITIVE = [
  { need: "Autocomplete latency", cloud: "500-2000 ms (network-bound)", us: "<100 ms (local)" },
  { need: "Private / offline work", cloud: "Limited without connection", us: "Full offline mode, AI still works" },
  { need: "Agentic tasks", cloud: "Strong but one-size-fits-all", us: "Dedicated cloud pipeline with RAG + tool loops" },
  { need: "Mac integration", cloud: "Electron-based, browser-like", us: "Native SwiftUI + AppKit, Apple Silicon optimised" },
  { need: "Privacy", cloud: "All code sent to cloud", us: "Local-by-default; cloud is opt-in" },
  { need: "Cost", cloud: "$15-20/mo+ per seat", us: "Local is free; cloud is usage-based" },
] as const;

export const ROADMAP = [
  { phase: "v1.0", items: ["FIM autocomplete <100ms", "Inline AI popover", "HNSW semantic search", "Cloud agent pipeline", "Offline mode"] },
  { phase: "v1.5", items: ["Experience engine (learns your patterns)", "Deeper Mac integration (Shortcuts, Spotlight)", "SSH remote sessions", "Project memory"] },
  { phase: "v2.0", items: ["Best-in-class cloud orchestration", "Extensions / plugin SDK", "Enterprise SSO & compliance", "Custom fine-tuning pipeline"] },
] as const;
