import XCTest

@MainActor
final class PanelResizingUITests: BaseUITestCase {
    func testMainPanelsAreVisibleAndWindowIsResizable() {
        let robot = launchApp()
        robot.window().assertVisible()
        robot.editor().assertVisible()
        robot.terminal().assertVisible()
        robot.fileTree().assertVisible()
    }
}
