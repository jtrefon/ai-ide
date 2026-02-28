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

    func testTypeScriptHighlightingDiagnosticsPresentForRealWorldSnippet() {
        let robot = launchApp(scenario: "typescript_realworld_highlighting")
        robot.editor().assertVisible()
        robot.editor().assertHighlightDiagnosticsContain([
            "lang=typescript",
            "module=typescript",
            "keyword=true",
            "type=true",
            "string=true",
            "boolean=true",
            "comment=true"
        ])
    }
}
