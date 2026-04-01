import XCTest
@testable import osx_ide

@MainActor
final class CompletionTriggerPolicyTests: XCTestCase {
    func testAutomaticRequestRequiresEnabledFeatureAndNoSelection() {
        let policy = CompletionTriggerPolicy()
        let disabledSettings = InlineCompletionSettings.default.with(isEnabled: false)
        let enabledSettings = InlineCompletionSettings.default

        let noSelection = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/Test.swift",
            language: "swift",
            buffer: "let value = ",
            cursorPosition: 12,
            selectionLength: 0,
            triggerReason: .automatic
        )

        let selectedText = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/Test.swift",
            language: "swift",
            buffer: "let value = 42",
            cursorPosition: 0,
            selectionLength: 2,
            triggerReason: .automatic
        )

        XCTAssertFalse(policy.decision(for: noSelection, settings: disabledSettings, recentSlowCompletions: 0).shouldRequest)
        XCTAssertFalse(policy.decision(for: selectedText, settings: enabledSettings, recentSlowCompletions: 0).shouldRequest)
        XCTAssertTrue(policy.decision(for: noSelection, settings: enabledSettings, recentSlowCompletions: 0).shouldRequest)
    }

    func testManualTriggerBypassesUnsupportedLanguageGuard() {
        let policy = CompletionTriggerPolicy()
        let snapshot = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: nil,
            language: "unknown-language",
            buffer: "foo",
            cursorPosition: 3,
            selectionLength: 0,
            triggerReason: .manual
        )

        let decision = policy.decision(for: snapshot, settings: .default, recentSlowCompletions: 0)
        XCTAssertTrue(decision.shouldRequest)
        XCTAssertEqual(decision.debounceMilliseconds, 0)
    }
}

private extension InlineCompletionSettings {
    func with(isEnabled: Bool) -> InlineCompletionSettings {
        InlineCompletionSettings(
            isEnabled: isEnabled,
            debounceMilliseconds: debounceMilliseconds,
            aggressiveness: aggressiveness,
            maxSuggestionLength: maxSuggestionLength,
            multilineEnabled: multilineEnabled,
            retrievalEnabled: retrievalEnabled,
            routingMode: routingMode,
            debugOverlayEnabled: debugOverlayEnabled
        )
    }
}
