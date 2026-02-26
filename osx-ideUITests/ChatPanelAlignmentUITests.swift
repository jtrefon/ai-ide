import XCTest

@MainActor
final class ChatPanelAlignmentUITests: BaseUITestCase {
    func testChatPanelControlsAreVisibleAndInteractive() {
        let robot = launchApp()
        let chat = robot.chat()
        chat.assertVisible()

        chat.newConversation.click()
        XCTAssertTrue(chat.send.exists, "Chat send button should remain visible after send")
    }

    func testChatInputUsesProductionMultilineTextView() {
        let robot = launchApp()
        let chat = robot.chat()
        chat.assertVisible()

        let multilineInput = app.textViews[UITestAccessibilityID.aiChatInputTextView]
        XCTAssertTrue(
            multilineInput.waitForExistence(timeout: 10),
            "Chat input must use production multiline text view in UITests"
        )
    }
}
