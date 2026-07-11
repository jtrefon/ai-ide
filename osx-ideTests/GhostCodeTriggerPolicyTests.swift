import XCTest
@testable import osx_ide

@MainActor
final class GhostCodeTriggerPolicyTests: XCTestCase {
    private func snapshot(
        buffer: String = "func foo() {\n    ",
        cursor: Int = 16,
        selectionLength: Int = 0,
        isComposingText: Bool = false,
        language: String = "swift"
    ) -> InlineCompletionEditorSnapshot {
        InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: nil,
            language: language,
            buffer: buffer,
            cursorPosition: cursor,
            selectionLength: selectionLength,
            isComposingText: isComposingText,
            triggerReason: .automatic
        )
    }

    func test_autoTrigger_allowsOnPause() {
        let policy = GhostCodeTriggerPolicy()
        let snap = snapshot(buffer: "func foo() {\n    ", cursor: 16)
        XCTAssertTrue(policy.shouldAutoTrigger(for: snap, idleMs: 500))
    }

    func test_autoTrigger_suppressesDuringComposition() {
        let policy = GhostCodeTriggerPolicy()
        let snap = snapshot(isComposingText: true)
        XCTAssertFalse(policy.shouldAutoTrigger(for: snap, idleMs: 500))
    }

    func test_autoTrigger_suppressesWithSelection() {
        let policy = GhostCodeTriggerPolicy()
        let snap = snapshot(selectionLength: 2)
        XCTAssertFalse(policy.shouldAutoTrigger(for: snap, idleMs: 500))
    }

    func test_autoTrigger_suppressesIfNotIdle() {
        let policy = GhostCodeTriggerPolicy()
        let snap = snapshot()
        XCTAssertFalse(policy.shouldAutoTrigger(for: snap, idleMs: 100))
    }

    func test_autoTrigger_suppressesForUnsupportedLanguage() {
        let policy = GhostCodeTriggerPolicy()
        let snap = snapshot(language: "unknown")
        XCTAssertFalse(policy.shouldAutoTrigger(for: snap, idleMs: 500))
    }

    func test_manualTrigger_allowsWithBuffer() {
        let policy = GhostCodeTriggerPolicy()
        let snap = snapshot()
        XCTAssertTrue(policy.shouldManualTrigger(for: snap))
    }

    func test_manualTrigger_suppressesWithEmptyBuffer() {
        let policy = GhostCodeTriggerPolicy()
        let snap = snapshot(buffer: "", cursor: 0)
        XCTAssertFalse(policy.shouldManualTrigger(for: snap))
    }

    func test_manualTrigger_suppressesDuringComposition() {
        let policy = GhostCodeTriggerPolicy()
        let snap = snapshot(isComposingText: true)
        XCTAssertFalse(policy.shouldManualTrigger(for: snap))
    }

    func test_autoTrigger_cursorAtEndOfLine() {
        let policy = GhostCodeTriggerPolicy()
        let snap = snapshot(buffer: "func foo() {\n    ", cursor: 16)
        XCTAssertTrue(policy.shouldAutoTrigger(for: snap, idleMs: 500))
    }

    func test_autoTrigger_cursorInMiddleOfLine_suppresses() {
        let policy = GhostCodeTriggerPolicy()
        let snap = snapshot(buffer: "func foo() {\n    let x = ", cursor: 20)
        XCTAssertFalse(policy.shouldAutoTrigger(for: snap, idleMs: 500))
    }
}
