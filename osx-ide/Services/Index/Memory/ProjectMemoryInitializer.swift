import Foundation

/// Analyzes the project using an LLM to generate mid-term memories about tech stack,
/// standards, and architecture. Runs once per project as a background task.
final class ProjectMemoryInitializer {
    private let index: CodebaseIndexProtocol
    private let aiService: AIService
    private let projectRoot: URL

    init(index: CodebaseIndexProtocol, aiService: AIService, projectRoot: URL) {
        self.index = index
        self.aiService = aiService
        self.projectRoot = projectRoot
    }

    /// Initialize project memories if they don't already exist.
    /// Returns true if memories were created, false if skipped (already exists or error).
    func initializeIfEmpty() async -> Bool {
        // Check if mid-term memories already exist
        do {
            let existing = try await index.getMemories(tier: .midTerm)
            if !existing.isEmpty {
                Swift.print("[ProjectMemory] Skipping — \(existing.count) mid-term memories already exist")
                return false
            }
        } catch {
            Swift.print("[ProjectMemory] Failed to check existing memories: \(error)")
            return false
        }

        // Collect project files
        let files = collectProjectFiles()
        guard !files.isEmpty else {
            Swift.print("[ProjectMemory] No project files found")
            return false
        }

        // Build prompt for LLM analysis
        let prompt = buildAnalysisPrompt(files: files)

        // Call LLM
        do {
            let response = try await aiService.generateCode(prompt)
            let memories = parseMemories(from: response)
            guard !memories.isEmpty else {
                Swift.print("[ProjectMemory] LLM returned no memories")
                return false
            }

            // Store memories
            var stored = 0
            for memory in memories {
                do {
                    _ = try await index.addMemory(
                        content: memory.content,
                        tier: .midTerm,
                        category: memory.category
                    )
                    stored += 1
                } catch {
                    Swift.print("[ProjectMemory] Failed to store memory: \(error)")
                }
            }

            Swift.print("[ProjectMemory] Stored \(stored) mid-term memories")
            return stored > 0
        } catch {
            Swift.print("[ProjectMemory] LLM call failed: \(error)")
            return false
        }
    }

    // MARK: - File Collection

    private func collectProjectFiles() -> [String: String] {
        var files: [String: String] = [:]

        // Key manifest files
        let manifestFiles = [
            "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
            "Cargo.toml", "Cargo.lock", "go.mod", "go.sum",
            "Gemfile", "Gemfile.lock", "Podfile", "Podfile.lock",
            "requirements.txt", "Pipfile", "Pipfile.lock", "pyproject.toml", "setup.py", "setup.cfg",
            "build.gradle", "build.gradle.kts", "pom.xml", "gradle.properties",
            "mix.exs", "mix.lock",
            "pubspec.yaml",
            "deno.json", "deno.lock",
            "composer.json", "composer.lock",
            "Makefile", "CMakeLists.txt",
            "Stack.toml", "cabal.project",
        ]

        // Config files
        let configFiles = [
            "tsconfig.json", ".eslintrc", ".eslintrc.json", ".eslintrc.js", ".eslintrc.cjs",
            ".prettierrc", ".prettierrc.json", ".prettierrc.js",
            "swiftlint.yml", "swiftlint.yaml",
            ".editorconfig",
            "tailwind.config.js", "tailwind.config.ts", "postcss.config.js",
            "next.config.js", "next.config.mjs", "next.config.ts",
            "nuxt.config.js", "nuxt.config.ts",
            "vite.config.js", "vite.config.ts",
            "webpack.config.js", "rollup.config.js", "svelte.config.js",
            "jest.config.js", "jest.config.ts", "vitest.config.ts",
            ".swiftlint.yml", ".swiftformat",
            ".gitignore", ".dockerignore",
            "Dockerfile", "docker-compose.yml", "docker-compose.yaml",
            ".swift-version", ".nvmrc", ".node-version",
            "biome.json", "biome.jsonc",
        ]

        // Readme and docs
        let docFiles = [
            "README.md", "README.txt", "README",
            "CONTRIBUTING.md", "CHANGELOG.md", "LICENSE", "LICENSE.md",
        ]

        let allFiles = manifestFiles + configFiles + docFiles

        for fileName in allFiles {
            let fileURL = projectRoot.appendingPathComponent(fileName)
            if let content = readLimited(fileURL, maxSize: 8_000) {
                files[fileName] = content
            }
        }

        // Also get project structure (top-level) for context
        if let structure = getProjectStructure(maxDepth: 2) {
            files[".structure"] = structure
        }

        return files
    }

    private func readLimited(_ url: URL, maxSize: Int) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard data.count <= maxSize else {
            // Truncate but read first N bytes
            return String(bytes: data.prefix(maxSize), encoding: .utf8)?.appending("\n... [truncated]")
        }
        return String(data: data, encoding: .utf8)
    }

    private func getProjectStructure(maxDepth: Int) -> String? {
        var lines: [String] = []
        enumerateDirectory(at: projectRoot, depth: 0, maxDepth: maxDepth, prefix: "", lines: &lines)
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private func enumerateDirectory(at url: URL, depth: Int, maxDepth: Int, prefix: String, lines: inout [String]) {
        guard depth < maxDepth else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let exclusion = ToolFileExclusion(projectRoot: projectRoot)

        let sorted = contents.sorted { lhs, rhs in
            let lhsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let rhsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if lhsDir != rhsDir { return lhsDir }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }

        for (idx, item) in sorted.enumerated() {
            let isLast = idx == sorted.count - 1
            let connector = isLast ? "└── " : "├── "
            let childPrefix = prefix + (isLast ? "    " : "│   ")

            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if exclusion.shouldExclude(item) {
                if isDir {
                    lines.append(prefix + connector + item.lastPathComponent + "/ (excluded)")
                }
                continue
            }

            let name = isDir ? item.lastPathComponent + "/" : item.lastPathComponent
            lines.append(prefix + connector + name)

            if isDir {
                enumerateDirectory(at: item, depth: depth + 1, maxDepth: maxDepth, prefix: childPrefix, lines: &lines)
            }
        }
    }

    // MARK: - Prompt Building

    private func buildAnalysisPrompt(files: [String: String]) -> String {
        var prompt = """
You are a software architect analyzing a project. Based on the provided project files, generate mid-term memories that capture the project's tech stack, conventions, and architecture.

Return memories in the following exact format:

## CATEGORY: <category>
MEMORY: <concise fact about the project>

Use these categories:
- tech_stack: Languages, frameworks, libraries, package manager, runtime
- standards: Coding style, linting rules, formatting, testing approach
- architecture: Project structure patterns, key directories, architectural decisions
- build: Build system, CI/CD, deployment, containerization

Rules:
- Each MEMORY should be a single concise sentence or bullet point
- Be specific: name versions, patterns, and conventions
- Only include facts that can be derived from the provided files
- Do NOT include generic advice — only project-specific information
- Aim for 5-15 memories total across all categories
"""

        for (fileName, content) in files.sorted(by: { $0.key < $1.key }) {
            prompt += "\n--- \(fileName) ---\n"
            prompt += content
            prompt += "\n"
        }

        return prompt
    }

    // MARK: - Response Parsing

    private struct ParsedMemory {
        let category: String
        let content: String
    }

    private func parseMemories(from response: String) -> [ParsedMemory] {
        var memories: [ParsedMemory] = []

        let lines = response.split(separator: "\n")
        var currentCategory = "general"

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for category header
            if trimmed.hasPrefix("## CATEGORY:") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count >= 2 {
                    currentCategory = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // Check for memory entry
            if trimmed.hasPrefix("MEMORY:") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count >= 2 {
                    let content = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        memories.append(ParsedMemory(category: currentCategory, content: content))
                    }
                }
            }
        }

        return memories
    }
}
