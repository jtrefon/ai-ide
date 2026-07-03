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
            // Load per-tool prompts from the v2 tool prompts directory
            let toolPromptKeys = [
                "Tools/v2/read_file",
                "Tools/v2/write_file",
                "Tools/v2/patch_file",
                "Tools/v2/list_files",
                "Tools/v2/search_project",
                "Tools/v2/web_search",
                "Tools/v2/web_browse",
                "Tools/v2/run_command",
                "Tools/v2/grep",
                "Tools/v2/find_file",
                "Tools/v2/delete_file",
                "Tools/v2/get_project_structure",
                "Tools/v2/plan",
                
                
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
