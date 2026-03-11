import XCTest

@MainActor
final class PanelResizingUITests: BaseUITestCase {
    func testSidebarAndChatResizeHandlesExistAndAreInteractive() {
        let robot = launchApp()
        robot.window().assertVisible()

        let sidebar = app.outlines[UITestAccessibilityID.fileExplorerOutline]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), "Sidebar must exist")
        let initialSidebarWidth = sidebar.frame.width

        let sidebarHandle = app.descendants(matching: .any)[UITestAccessibilityID.sidebarResizeHandle].firstMatch
        XCTAssertTrue(sidebarHandle.waitForExistence(timeout: 10), "Sidebar resize handle must exist")
        let sidebarStart = sidebarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let sidebarTarget = sidebarStart.withOffset(CGVector(dx: 120, dy: 0))
        sidebarStart.press(forDuration: 0.1, thenDragTo: sidebarTarget)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertGreaterThan(abs(sidebar.frame.width - initialSidebarWidth), 20, "Sidebar width should change after drag")

        let chatHandle = app.descendants(matching: .any)[UITestAccessibilityID.chatResizeHandle].firstMatch
        XCTAssertTrue(chatHandle.waitForExistence(timeout: 10), "Chat resize handle must exist")
        let initialChatHandleX = chatHandle.frame.minX
        let chatStart = chatHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let chatTarget = chatStart.withOffset(CGVector(dx: -120, dy: 0))
        chatStart.press(forDuration: 0.1, thenDragTo: chatTarget)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertGreaterThan(
            abs(chatHandle.frame.minX - initialChatHandleX),
            20,
            "Chat panel geometry should change after chat divider drag"
        )
    }
}
