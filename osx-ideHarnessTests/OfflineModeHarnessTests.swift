import XCTest
@testable import osx_ide

/// Dedicated offline harness tests.
/// These tests validate offline-specific behavior and should be run separately
/// from production-parity online harness suites.
@MainActor
final class OfflineModeHarnessTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await TestConfigurationProvider.shared.setConfiguration(.isolated)
    }

    override func tearDown() async throws {
        await TestConfigurationProvider.shared.resetToDefault()
        try await super.tearDown()
    }

    func testOfflineHarnessRejectsAgentMode() async throws {
        let runtime = try await makeRuntime(offlineModeEnabled: true)
        let manager = runtime.manager
        manager.currentMode = .agent

        manager.currentInput = "Create a file named offline-test.txt"
        manager.sendMessage()

        try await waitForConversationToFinish(manager, timeoutSeconds: 30)
        let errorText = manager.error ?? ""
        XCTAssertTrue(
            errorText.contains("Agent mode is unavailable in Offline Mode"),
            "Expected offline-mode agent gating error, got: \(errorText)"
        )
    }

    func testOfflineHarnessBlocksExternalAPIsWhenOfflineDisabled() async throws {
        let runtime = try await makeRuntime(offlineModeEnabled: false)
        let manager = runtime.manager
        manager.currentMode = .agent

        manager.currentInput = "Create a file named api-blocked.txt"
        manager.sendMessage()

        try await waitForConversationToFinish(manager, timeoutSeconds: 30)
        let errorText = manager.error ?? ""
        XCTAssertTrue(
            errorText.contains("External APIs are disabled in test configuration"),
            "Expected external API block error, got: \(errorText)"
        )
    }

    private struct Runtime {
        let manager: ConversationManager
    }

    private func makeRuntime(offlineModeEnabled: Bool) async throws -> Runtime {
        let container = DependencyContainer(
            launchContext: AppLaunchContext(
                mode: .unitTest,
                isTesting: true,
                isUITesting: false,
                testProfilePath: nil,
                disableHeavyInit: false
            )
        )

        let selectionStore = LocalModelSelectionStore(settingsStore: container.settingsStore)
        await selectionStore.setOfflineModeEnabled(offlineModeEnabled)
        let effectiveOfflineMode = await selectionStore.isOfflineModeEnabled()
        XCTAssertEqual(effectiveOfflineMode, offlineModeEnabled)

        guard let manager = container.conversationManager as? ConversationManager else {
            throw NSError(
                domain: "OfflineModeHarnessTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected conversation manager type"]
            )
        }

        return Runtime(manager: manager)
    }

    private func waitForConversationToFinish(
        _ manager: ConversationManager,
        timeoutSeconds: TimeInterval
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !manager.isSending {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if !manager.isSending {
            return
        }
        XCTFail("Timed out waiting for conversation manager to finish send task")
    }
}
