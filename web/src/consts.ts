export const SITE_TITLE = "Compass | The native AI IDE for macOS";
export const SITE_DESCRIPTION =
  "Compass is a Swift-native AI IDE that runs real AI — completion, RAG, and agentic coding — entirely on your Apple Silicon. 200MB. No Electron. Your code never leaves your Mac.";

export const BASE_URL = "/ai-ide";
export const SITE_URL = "https://jtrefon.github.io/ai-ide";
export const REPO = "https://github.com/jtrefon/ai-ide";
export const RELEASES = `${REPO}/releases`;

/** Replace this with your Formspree form ID (or other static-form backend URL) */
export const BETA_FORM_ACTION = "https://formspree.io/f/";

export const NAV = [
  { label: "Developers", href: "/developers" },
  { label: "Teams", href: "/teams" },
  { label: "Enterprise", href: "/enterprise" },
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
  { title: "Real FIM completion", desc: `Genuine on-device intelligence - ghost-text completion in <100ms from a 1.5B model, not a fake heuristic. Tuned for instant cancellation and tight prompts.` },
  { title: "Built-in local inference", desc: `MLX-backed models run chat, quick actions, and full agentic workflows on your Mac. Offline. Private. No API key required.` },
  { title: "ANE-accelerated RAG", desc: `Embeddings and retrieval run on the Apple Neural Engine - indexing and search stay silent and painless, never hogging your CPU.` },
  { title: "Codebase intelligence", desc: `SQLite FTS5 plus HNSW vector retrieval over files, symbols, and chunks - grounded answers drawn from your own code.` },
  { title: "Built-in web browser", desc: `Read docs and references without leaving the editor. One app, zero context-switching to a browser.` },
  { title: "Provider choice", desc: `Route heavy work through any provider - OpenRouter, Alibaba Cloud, DeepSeek, Kilo Code, or your own local model.` },
  { title: "Inline AI popover", desc: `Cursor-anchored Q&A for instant explain, refactor, or ask - without losing your place in the code.` },
  { title: "Semantic search", desc: `HNSW ANN vector index with CoreML embeddings, 10-50x faster than brute-force with ~95-99% recall.` },
] as const;

export const FEATURES_BETA = [
  { title: "Local agentic execution", desc: `The agent runs on-device for maximum security - your most sensitive refactors never touch a cloud.` },
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
  { need: "Where your code goes", cloud: "Sent to a cloud server every keystroke", us: "Local-by-default; cloud is opt-in" },
  { need: "Embeddings / RAG", cloud: "Cloud-bound, ships code out", us: "On-device, Apple Neural Engine" },
  { need: "Agentic tasks", cloud: "Strong but one-size-fits-all", us: "Dedicated pipeline, runs locally for privacy" },
  { need: "Mac integration", cloud: "Electron-based, browser-like", us: "Native AppKit + Liquid Glass, Apple Silicon" },
  { need: "Memory footprint", cloud: "Electron - 1GB+ and climbing", us: "~200MB with all AI on" },
  { need: "Cost", cloud: "$15-20/mo+ per seat", us: "Local is free; cloud is usage-based" },
] as const;

export const ROADMAP = [
  { phase: "v1.0", items: ["FIM autocomplete <100ms", "Inline AI popover", "HNSW semantic search", "Cloud agent pipeline", "Offline mode"] },
  { phase: "v1.5", items: ["Experience engine (learns your patterns)", "Deeper Mac integration (Shortcuts, Spotlight)", "SSH remote sessions", "Project memory"] },
  { phase: "v2.0", items: ["Best-in-class cloud orchestration", "Extensions / plugin SDK", "Enterprise SSO & compliance", "Custom fine-tuning pipeline"] },
] as const;
