import XCTest

@MainActor
final class LayoutPersistenceUITests: BaseUITestCase {
    func testSidebarWidthPersistsAcrossRelaunch() {
        let firstLaunch = launchApp()
        firstLaunch.window().assertVisible()

        let sidebar = app.outlines[UITestAccessibilityID.fileExplorerOutline]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), "Sidebar file tree must exist")

        let initialWidth = sidebar.frame.width
        let splitter = app.splitGroups.firstMatch.splitters.firstMatch
        XCTAssertTrue(splitter.waitForExistence(timeout: 10), "Sidebar splitter must exist")
        let dragStart = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        var candidateWidths: [CGFloat] = []

        let dragRight = dragStart.withOffset(CGVector(dx: 140, dy: 0))
        dragStart.press(forDuration: 0.1, thenDragTo: dragRight)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        candidateWidths.append(sidebar.frame.width)

        let dragLeft = dragStart.withOffset(CGVector(dx: -140, dy: 0))
        dragStart.press(forDuration: 0.1, thenDragTo: dragLeft)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        candidateWidths.append(sidebar.frame.width)

        guard let changedWidth = candidateWidths.max(by: {
            abs($0 - initialWidth) < abs($1 - initialWidth)
        }) else {
            XCTFail("Sidebar width sampling failed")
            return
        }
        XCTAssertGreaterThan(
            abs(changedWidth - initialWidth),
            25,
            "Sidebar width should change after splitter drag"
        )

        app.terminate()

        let secondLaunch = launchApp()
        secondLaunch.window().assertVisible()

        let restoredSidebar = app.outlines[UITestAccessibilityID.fileExplorerOutline]
        XCTAssertTrue(restoredSidebar.waitForExistence(timeout: 10), "Sidebar file tree must exist after relaunch")
        XCTAssertGreaterThan(
            abs(restoredSidebar.frame.width - changedWidth),
            60,
            "Sidebar width should persist after relaunch (within tolerance)"
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
}
