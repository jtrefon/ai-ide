import XCTest

@MainActor
final class LayoutPersistenceUITests: BaseUITestCase {
    func testSidebarWidthPersistsAcrossRelaunch() {
        let firstLaunch = launchApp()
        firstLaunch.window().assertVisible()

        let sidebar = app.outlines[UITestAccessibilityID.fileExplorerOutline]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), "Sidebar file tree must exist")
        let initialWidth = sidebar.frame.width

        app.terminate()

        let secondLaunch = launchApp()
        secondLaunch.window().assertVisible()

        let restoredSidebar = app.outlines[UITestAccessibilityID.fileExplorerOutline]
        XCTAssertTrue(restoredSidebar.waitForExistence(timeout: 10), "Sidebar file tree must exist after relaunch")
        XCTAssertLessThan(
            abs(restoredSidebar.frame.width - initialWidth),
            30,
            "Sidebar width should remain stable across relaunch in isolated profile"
        )
    }

    func testTerminalIsVisibleAndOnscreenOnLaunch() {
        let robot = launchApp()
        robot.window().assertVisible()

        let terminal = app.descendants(matching: .any)[UITestAccessibilityID.terminalTextView].firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 10), "Terminal must be visible on launch")

        let windowFrame = robot.window().mainWindow.frame
        XCTAssertGreaterThanOrEqual(terminal.frame.minY, windowFrame.minY + 1)
        XCTAssertLessThanOrEqual(terminal.frame.maxY, windowFrame.maxY)
    }

    func testBottomAndRightPanelsAreVisibleWithinWindowOnLaunch() {
        let robot = launchApp()
        robot.window().assertVisible()

        let windowFrame = robot.window().mainWindow.frame

        let chatSendButton = app.buttons[UITestAccessibilityID.aiChatSendButton]
        XCTAssertTrue(chatSendButton.waitForExistence(timeout: 10), "Chat panel controls must be visible")
        XCTAssertGreaterThanOrEqual(chatSendButton.frame.minX, windowFrame.minX)
        XCTAssertLessThanOrEqual(chatSendButton.frame.maxX, windowFrame.maxX)
    }
}
