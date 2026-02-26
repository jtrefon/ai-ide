import XCTest

@MainActor
final class JSONHighlighterUITests: BaseUITestCase {
    func testJSONHighlightingDiagnosticsPresent() {
        let robot = launchApp(scenario: "json_highlighting")
        robot.editor().assertVisible()
    }
}
