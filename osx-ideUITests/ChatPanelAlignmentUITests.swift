import XCTest

@MainActor
final class ChatPanelAlignmentUITests: BaseUITestCase {
    func testChatPanelControlsAreVisibleAndInteractive() {
        let robot = launchApp()
        let chat = robot.chat()
        chat.assertVisible()

        chat.sendMessage("UI recovery validation")
        XCTAssertTrue(chat.send.exists, "Chat send button should remain visible after send")
    }
}
