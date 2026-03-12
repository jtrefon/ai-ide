        let template = try PromptRepository.shared.prompt(
            key: "ConversationFlow/FinalResponse/final_response_summary",
            defaultValue: Self.defaultFinalResponsePrompt,
            projectRoot: projectRoot
        )
