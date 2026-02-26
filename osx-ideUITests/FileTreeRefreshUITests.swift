import XCTest

@MainActor
final class FileTreeRefreshUITests: BaseUITestCase {
    func testFileTreeIsVisible() {
        let robot = launchApp()
        let tree = robot.fileTree()
        tree.assertVisible()
        XCTAssertTrue(tree.outline.isHittable, "File tree outline should be hittable")
    }
}
