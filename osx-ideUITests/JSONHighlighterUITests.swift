import XCTest

@MainActor
final class JSONHighlighterUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        let app = XCUIApplication()
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }

    func testJSONHighlighting_NotAllRed() throws {
        let app = XCUIApplication()
        app.launchEnvironment["XCUI_TESTING"] = "1"
        app.launchEnvironment["UI_TEST_SCENARIO"] = "json_highlighting"
        app.launch()

        let mainWindow = app.windows.firstMatch
        if !mainWindow.waitForExistence(timeout: 15) {
            XCTSkip("Main window not discoverable by XCTest on this machine/session")
        }

        let editor = app.textViews["CodeEditorTextView"]
        if !editor.waitForExistence(timeout: 15) {
            XCTSkip("Code editor not discoverable by XCTest on this machine/session")
        }

        // This is a hidden overlay in CodeEditorView, only present when XCUI_TESTING=1.
        let diagnostics = app.staticTexts["EditorHighlightDiagnostics"]
        if !diagnostics.waitForExistence(timeout: 15) {
            XCTFail("Expected EditorHighlightDiagnostics element to exist")
            return
        }

        // Wait for highlight pass to run and publish diagnostics.
        // Use label here (more reliable than `value` for staticTexts).
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", "lang=json")
        expectation(for: predicate, evaluatedWith: diagnostics, handler: nil)
        waitForExpectations(timeout: 15)

        let value = diagnostics.label

        XCTAssertTrue(value.contains("lang=json"), "Expected diagnostics to report json highlighting. Got: \(value)")
        XCTAssertTrue(value.contains("key=true"), "Expected key color (from JSONModule) to be present. Got: \(value)")
        XCTAssertTrue(value.contains("brace=true"), "Expected brace color (from JSONModule) to be present. Got: \(value)")
        XCTAssertTrue(value.contains("colon=true"), "Expected colon color (from JSONModule) to be present. Got: \(value)")

        // If everything is red, unique colors will be very low (usually 1-2 including labelColor).
        // Require at least 4 distinct colors.
        if let uniquePart = value.split(separator: ";").first(where: { $0.hasPrefix("unique=") }),
           let uniqueCount = Int(uniquePart.split(separator: "=").last ?? "") {
            XCTAssertGreaterThanOrEqual(uniqueCount, 4, "Expected at least 4 unique colors, got \(uniqueCount). Full diagnostics: \(value)")
        } else {
            XCTFail("Could not parse unique= from diagnostics: \(value)")
        }
    }
}
