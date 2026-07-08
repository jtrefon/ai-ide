import { c as createComponent, m as maybeRenderHead, b as addAttribute, a as renderTemplate, e as createAstro, d as renderScript, r as renderComponent, f as renderSlot, g as renderHead, u as unescapeHTML } from './astro/server_WUFD8Sh7.mjs';
import 'piccolore';
/* empty css                        */
import 'clsx';

const SITE_TITLE = "Compass | Native AI IDE for macOS";
const SITE_DESCRIPTION = "A Swift-native AI IDE for developers who want local speed, private context, and serious agentic coding without giving up control.";
const BASE_URL = "/ai-ide";
const REPO = "https://github.com/jtrefon/ai-ide";
const NAV = [
  { label: "Tech", href: "/tech" },
  { label: "Beta", href: "/beta" },
  { label: "Contributors", href: "/contributors" },
  { label: "Investors", href: "/investors" }
];
const FEATURES_SHIPPING = [
  { title: "On-device FIM autocomplete", desc: `<100ms ghost-text completion via local model, tuned for cancellation and compact prompts.` },
  { title: "Native local inference", desc: `MLX-backed models supporting offline chat, local quick actions, configurable context length and quantised KV cache.` },
  { title: "Codebase intelligence", desc: `SQLite FTS5 index tracking files, symbols, chunks, and HNSW-backed embedding retrieval for grounded answers.` },
  { title: "Provider choice", desc: `Route heavy work through any provider - OpenRouter, Alibaba Cloud, DeepSeek, Kilo Code, or your own local model.` },
  { title: "Inline AI popover", desc: `Cursor-anchored Q&A panel for instant explain, refactor, or ask - without switching context.` },
  { title: "Semantic search", desc: `HNSW ANN vector index with CoreML embeddings, 10-50x faster than brute-force with ~95-99% recall.` }
];
const FEATURES_BETA = [
  { title: "Agentic tool execution", desc: `Orchestration graph (Planner > Worker > QA > Final) with 20+ tools, stall detection, and recovery.` },
  { title: "Multi-file refactoring", desc: `Autonomous execution of complex multi-file changes with diff-preview and checkpoint rollback.` },
  { title: "Remote sessions", desc: `SSH and SFTP integration so the agent works in your infrastructure.` },
  { title: "Project memory", desc: `Adaptive rules and inspectable memories that teach the assistant your conventions per-repository.` }
];
const PIPELINE_LOCAL = [
  { feature: "Latency", value: "<100 ms" },
  { feature: "Model", value: "On-device LLM via MLX" },
  { feature: "Privacy", value: "100% offline, no data leaves your machine" },
  { feature: "Tasks", value: "FIM completion, inline Q&A, semantic search, quick transforms" },
  { feature: "Network", value: "No internet required" }
];
const PIPELINE_CLOUD = [
  { feature: "Latency", value: "5-30 s (task-dependent)" },
  { feature: "Model", value: "Any provider via OpenRouter or direct API" },
  { feature: "Privacy", value: "Opt-in; you choose when code is sent" },
  { feature: "Tasks", value: "Agentic refactors, multi-file planning, tool orchestration, review" },
  { feature: "Network", value: "Requires internet, full offline fallback" }
];
const COMPETITIVE = [
  { need: "Autocomplete latency", cloud: "500-2000 ms (network-bound)", us: "<100 ms (local)" },
  { need: "Private / offline work", cloud: "Limited without connection", us: "Full offline mode, AI still works" },
  { need: "Agentic tasks", cloud: "Strong but one-size-fits-all", us: "Dedicated cloud pipeline with RAG + tool loops" },
  { need: "Mac integration", cloud: "Electron-based, browser-like", us: "Native SwiftUI + AppKit, Apple Silicon optimised" },
  { need: "Privacy", cloud: "All code sent to cloud", us: "Local-by-default; cloud is opt-in" },
  { need: "Cost", cloud: "$15-20/mo+ per seat", us: "Local is free; cloud is usage-based" }
];
const ROADMAP = [
  { phase: "v1.0", items: ["FIM autocomplete <100ms", "Inline AI popover", "HNSW semantic search", "Cloud agent pipeline", "Offline mode"] },
  { phase: "v1.5", items: ["Experience engine (learns your patterns)", "Deeper Mac integration (Shortcuts, Spotlight)", "SSH remote sessions", "Project memory"] },
  { phase: "v2.0", items: ["Best-in-class cloud orchestration", "Extensions / plugin SDK", "Enterprise SSO & compliance", "Custom fine-tuning pipeline"] }
];

const $$Header = createComponent(($$result, $$props, $$slots) => {
  return renderTemplate`${maybeRenderHead()}<header class="site-header"> <a class="brand"${addAttribute(`${BASE_URL}/`, "href")} aria-label="Compass home"> <img${addAttribute(`${BASE_URL}/images/logo-compass.svg`, "src")} alt="" width="28" height="28"> <span>Compass</span> </a> <nav class="topnav" aria-label="Primary navigation"> ${NAV.map(
    (item) => item.href.startsWith("http") ? renderTemplate`<a${addAttribute(item.href, "href")} target="_blank" rel="noreferrer">${item.label}</a>` : renderTemplate`<a${addAttribute(BASE_URL + (item.href === "/" ? "/" : item.href), "href")}>${item.label}</a>`
  )} <a${addAttribute(REPO, "href")} target="_blank" rel="noreferrer" class="btn btn-secondary" style="padding:6px 14px;margin-left:4px;font-size:.8rem"> <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path></svg>
Source
</a> </nav> <button class="menu-toggle" aria-label="Toggle navigation" aria-expanded="false"> <span></span><span></span><span></span> </button> <div class="mobile-menu" id="mobile-menu"> ${NAV.map(
    (item) => item.href.startsWith("http") ? renderTemplate`<a${addAttribute(item.href, "href")} class="mobile-link" target="_blank" rel="noreferrer">${item.label}</a>` : renderTemplate`<a${addAttribute(BASE_URL + (item.href === "/" ? "/" : item.href), "href")} class="mobile-link">${item.label}</a>`
  )} <a${addAttribute(REPO, "href")} class="mobile-link" target="_blank" rel="noreferrer">GitHub</a> </div> </header>`;
}, "/Users/jack/Projects/osx/osx-ide/web/src/components/Header.astro", void 0);

const $$Footer = createComponent(($$result, $$props, $$slots) => {
  return renderTemplate`${maybeRenderHead()}<footer class="site-footer"> <div> <strong>Compass</strong> <span style="margin-left:8px">Native AI development for macOS.</span> <span style="margin-left:16px;color:var(--text-faint);font-size:.8rem">
Built by <a href="https://www.trefon.com" target="_blank" rel="noreferrer" style="color:var(--accent)">Jacek Trefon</a> </span> </div> <div> <a${addAttribute(`${REPO}`, "href")} style="margin-right:16px">GitHub</a> <a${addAttribute(`${BASE_URL}/beta`, "href")} style="margin-right:16px">Beta</a> <a${addAttribute(`${BASE_URL}/contributors`, "href")} style="margin-right:16px">Contributors</a> <a${addAttribute(`${BASE_URL}/investors`, "href")}>Investors</a> <span style="margin-left:16px;color:var(--text-faint)">&copy; <span id="year"></span> Jacek Trefon</span> </div> </footer>`;
}, "/Users/jack/Projects/osx/osx-ide/web/src/components/Footer.astro", void 0);

var __freeze = Object.freeze;
var __defProp = Object.defineProperty;
var __template = (cooked, raw) => __freeze(__defProp(cooked, "raw", { value: __freeze(cooked.slice()) }));
var _a;
const $$Astro = createAstro("https://jtrefon.github.io/ai-ide/");
const $$BaseLayout = createComponent(($$result, $$props, $$slots) => {
  const Astro2 = $$result.createAstro($$Astro, $$props, $$slots);
  Astro2.self = $$BaseLayout;
  const { title, description, canonical, ogImage } = Astro2.props;
  const pageTitle = title || SITE_TITLE;
  const pageDesc = description || SITE_DESCRIPTION;
  const pageUrl = canonical || `${BASE_URL}/`;
  const ogImg = ogImage || `https://jtrefon.github.io/ai-ide/images/og-image.svg`;
  const ldJSON = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "Compass",
    applicationCategory: "DeveloperApplication",
    operatingSystem: "macOS",
    description: "Native macOS AI IDE with local inference, inline completion, codebase retrieval, and cloud model orchestration.",
    softwareRequirements: "macOS on Apple Silicon",
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    codeRepository: REPO,
    author: { "@type": "Person", name: "Jacek Trefon", url: "https://www.trefon.com" }
  });
  return renderTemplate(_a || (_a = __template(['<html lang="en"> <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>', '</title><meta name="description"', '><meta name="theme-color" content="#06080d"><meta property="og:title"', '><meta property="og:description"', '><meta property="og:type" content="website"><meta property="og:url"', '><meta property="og:image"', '><meta name="twitter:card" content="summary_large_image"><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet"><link rel="icon" type="image/svg+xml"', '><link rel="canonical"', '><script type="application/ld+json">', "<\/script>", '</head> <body> <div class="grid-bg" aria-hidden="true"></div> <div class="bg-fx" aria-hidden="true"></div> ', " <main> ", " </main> ", " ", " </body> </html>"])), pageTitle, addAttribute(pageDesc, "content"), addAttribute(pageTitle, "content"), addAttribute(pageDesc, "content"), addAttribute(pageUrl, "content"), addAttribute(ogImg, "content"), addAttribute(`${BASE_URL}/images/favicon.svg`, "href"), addAttribute(pageUrl, "href"), unescapeHTML(ldJSON), renderHead(), renderComponent($$result, "Header", $$Header, {}), renderSlot($$result, $$slots["default"]), renderComponent($$result, "Footer", $$Footer, {}), renderScript($$result, "/Users/jack/Projects/osx/osx-ide/web/src/layouts/BaseLayout.astro?astro&type=script&index=0&lang.ts"));
}, "/Users/jack/Projects/osx/osx-ide/web/src/layouts/BaseLayout.astro", void 0);

export { $$BaseLayout as $, BASE_URL as B, COMPETITIVE as C, FEATURES_SHIPPING as F, PIPELINE_LOCAL as P, REPO as R, SITE_DESCRIPTION as S, FEATURES_BETA as a, ROADMAP as b, SITE_TITLE as c, PIPELINE_CLOUD as d };
