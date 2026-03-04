import XCTest

@MainActor
final class JSONHighlighterUITests: BaseUITestCase {
    func testJSONHighlightingDiagnosticsPresent() {
        let robot = launchApp(scenario: "json_highlighting")
        robot.editor().assertVisible()
        robot.editor().assertHighlightDiagnosticsContain([
            "lang=json",
            "module=json",
            "key=true",
            "string=true",
            "number=true",
            "bool=true",
            "null=true"
        ])
    }

    func testTypeScriptHighlightingDiagnosticsPresent() {
        let robot = launchApp(scenario: "typescript_highlighting")
        robot.editor().assertVisible()
        robot.editor().assertHighlightDiagnosticsContain([
            "lang=typescript",
            "module=typescript",
            "unique=",
            "comment=true",
            "string=true",
            "keyword=true"
        ])
    }

    func testTSXHighlightingDiagnosticsPresentForRealWorldSnippet() {
        let robot = launchApp(scenario: "tsx_realworld_highlighting")
        robot.editor().assertVisible()
        robot.editor().assertHighlightDiagnosticsContain([
            "lang=tsx",
            "module=tsx",
            "keyword=true",
            "type=true",
            "string=true",
            "comment=true",
            "tag=true",
            "attribute=true"
        ])
    }
}
