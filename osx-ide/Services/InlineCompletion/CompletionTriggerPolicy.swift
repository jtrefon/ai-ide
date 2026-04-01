import Foundation

struct CompletionTriggerPolicyDecision: Equatable {
    let shouldRequest: Bool
    let debounceMilliseconds: Int
}

@MainActor
struct CompletionTriggerPolicy {
    private let supportedLanguages: Set<String> = [
        "swift", "objective-c", "objective-cpp", "c", "cpp",
        "typescript", "tsx", "javascript", "jsx",
        "python", "json", "html", "css", "markdown", "yaml", "shell"
    ]

    func decision(
        for snapshot: InlineCompletionEditorSnapshot,
        settings: InlineCompletionSettings,
        recentSlowCompletions: Int
    ) -> CompletionTriggerPolicyDecision {
        guard settings.isEnabled else {
            return CompletionTriggerPolicyDecision(shouldRequest: false, debounceMilliseconds: settings.debounceMilliseconds)
        }

        guard snapshot.triggerReason == .manual || !snapshot.hasSelection else {
            return CompletionTriggerPolicyDecision(shouldRequest: false, debounceMilliseconds: settings.debounceMilliseconds)
        }

        guard !snapshot.buffer.isEmpty else {
            return CompletionTriggerPolicyDecision(shouldRequest: false, debounceMilliseconds: settings.debounceMilliseconds)
        }

        let normalizedLanguage = snapshot.language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard snapshot.triggerReason == .manual || supportedLanguages.contains(normalizedLanguage) else {
            return CompletionTriggerPolicyDecision(shouldRequest: false, debounceMilliseconds: settings.debounceMilliseconds)
        }

        let computedDebounce: Int
        if snapshot.triggerReason == .manual {
            computedDebounce = 0
        } else if recentSlowCompletions >= 3 {
            computedDebounce = min(900, Int(Double(settings.debounceMilliseconds) * 1.8))
        } else if recentSlowCompletions > 0 {
            computedDebounce = min(600, Int(Double(settings.debounceMilliseconds) * 1.25))
        } else {
            computedDebounce = settings.debounceMilliseconds
        }

        return CompletionTriggerPolicyDecision(shouldRequest: true, debounceMilliseconds: computedDebounce)
    }
}

