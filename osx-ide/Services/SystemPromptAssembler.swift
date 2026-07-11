import Foundation

struct SystemPromptAssembler {
    struct Input {
        let systemPromptOverride: String
        let hasTools: Bool
        let toolPromptMode: ToolPromptMode
        let mode: AIMode?
        let projectRoot: URL?
        let reasoningMode: ReasoningMode
        let stage: AIRequestStage?
        let includeModelReasoning: Bool
        let pinnedRules: [String]
    }

    func assemble(input: Input) throws -> String {
        var sections: [String] = []

        if !input.pinnedRules.isEmpty {
            sections.append("PINNED RULES (always follow, non-negotiable):\n" + input.pinnedRules.enumerated().map { i, rule in
                "\(i + 1). \(rule)"
            }.joined(separator: "\n"))
        }

        let systemPromptOverride = input.systemPromptOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if systemPromptOverride.isEmpty {
            sections.append(try PromptRepository.shared.prompt(
                key: "System/base-system-prompt",
                projectRoot: input.projectRoot
            ))
        } else {
            sections.append(systemPromptOverride)
        }

        if input.hasTools {
            sections.append(try PromptRepository.shared.prompt(
                key: input.toolPromptMode == .fullStatic
                    ? "System/tool-system-prompt-full"
                    : "System/tool-system-prompt-concise",
                projectRoot: input.projectRoot
            ))
            // Load per-tool prompts from the canonical v3 tool prompts directory.
            // NOTE: the previous v2 prompt set was removed; v3 is authoritative.
            let toolPromptKeys = [
                "Tools/v3/read",
                "Tools/v3/write",
                "Tools/v3/edit",
                "Tools/v3/ls",
                "Tools/v3/glob",
                "Tools/v3/search",
                "Tools/v3/rm",
                "Tools/v3/context",
                "Tools/v3/web_search",
                "Tools/v3/web_fetch",
                "Tools/v3/bash",
                "Tools/v3/plan"
            ]
            var toolPrompts: [String] = []
            for key in toolPromptKeys {
                if let prompt = try? PromptRepository.shared.prompt(key: key, projectRoot: input.projectRoot) {
                    toolPrompts.append(prompt)
                }
            }
            if !toolPrompts.isEmpty {
                sections.append("## Tool Reference\n\nEach tool below has WHAT (what it does), WHEN (when to use it), HOW (parameters and overloading), and OUTPUT (response format).\n\n" + toolPrompts.joined(separator: "\n\n---\n\n"))
            }
            if let envelope = try? PromptRepository.shared.prompt(
                key: "System/tool-execution-envelope",
                projectRoot: input.projectRoot
            ) {
                sections.append(envelope)
            }
        }

        if let mode = input.mode {
            sections.append(try PromptRepository.shared.prompt(
                key: mode == .agent ? "System/mode-agent" : mode == .coder ? "System/mode-coder" : "System/mode-chat",
                projectRoot: input.projectRoot
            ))
        }

        if let projectRoot = input.projectRoot {
            let projectRootContextTemplate = try PromptRepository.shared.prompt(
                key: "System/project-root-context",
                projectRoot: projectRoot
            )
            sections.append(
                projectRootContextTemplate.replacingOccurrences(
                    of: "{{PROJECT_ROOT_PATH}}",
                    with: projectRoot.path
                )
            )
        }

        if input.includeModelReasoning {
            sections.append(try PromptRepository.shared.prompt(
                key: input.reasoningMode.modelReasoningPromptKey,
                projectRoot: input.projectRoot
            ))
        }

        if let reasoningPrompt = try AIRequestStage.reasoningPromptIfNeeded(
            reasoningMode: input.reasoningMode,
            mode: input.mode,
            stage: input.stage,
            projectRoot: input.projectRoot
        ) {
            sections.append(reasoningPrompt)
        }

        // Inject OS context so the agent can use platform-native tools
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        sections.append("You are running on macOS \(osVersion). You can use standard macOS CLI tools (swift, python, node, grep, sed, awk, curl, etc.) via the run_command tool.")

        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
