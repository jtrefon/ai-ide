import XCTest

@MainActor
final class ChatPanelAlignmentUITests: XCTestCase {
    func testChatPanelLayoutIsWithinBounds() throws {
        let app = XCUIApplication()
        app.launch()
        
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10))
        
        let chatPanel = app.descendants(matching: .any).matching(identifier: "AIChatPanel").firstMatch
        if !chatPanel.exists {
            let viewMenu = app.menuBars.menuItems["View"]
            if viewMenu.exists {
                viewMenu.click()
                let toggleChat = viewMenu.menuItems["Toggle AI Chat"]
                if toggleChat.exists {
                    toggleChat.click()
                }
            }
        }
        
        if !chatPanel.waitForExistence(timeout: 5) {
            throw XCTSkip("Chat panel not discoverable")
        }
        
        // The text view is often deeply nested inside the ChatInputView
        let chatInput = app.textViews["AIChatInputTextView"]
        if !chatInput.waitForExistence(timeout: 5) {
            throw XCTSkip("Chat input not discoverable")
        }
        
        let sendButton = app.buttons["AIChatSendButton"]
        if !sendButton.waitForExistence(timeout: 5) {
            throw XCTSkip("Send button not discoverable")
        }
        
        let windowFrame = mainWindow.frame
        let inputFrame = chatInput.frame
        let sendButtonFrame = sendButton.frame
        let panelFrame = chatPanel.frame
        
        // Assert that the bottom of the send button is less than or equal to the bottom of the window
        XCTAssertLessThanOrEqual(sendButtonFrame.maxY, windowFrame.maxY)
        XCTAssertLessThanOrEqual(inputFrame.maxY, windowFrame.maxY)
        XCTAssertLessThanOrEqual(panelFrame.maxY, windowFrame.maxY)
    }
}
