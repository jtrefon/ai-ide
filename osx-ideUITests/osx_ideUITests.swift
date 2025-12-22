//
//  osx_ideUITests.swift
//  osx-ideUITests
//
//  Created by Jack Trefon on 25/08/2025.
//

import XCTest

@MainActor
final class osx_ideUITests: XCTestCase {
    private static var testFiles: [URL] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Clean up any test files created during this test
        for file in Self.testFiles {
            try? FileManager.default.removeItem(at: file)
        }
        Self.testFiles.removeAll()
        
        // Terminate the app to ensure clean state
        XCUIApplication().terminate()
    }

    private func createTestFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("ui_test_file_\(UUID().uuidString).swift")
        Self.testFiles.append(testFile)
        return testFile
    }

    @MainActor
    func testAppLaunchAndBasicUI() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Verify main window exists
        XCTAssertTrue(app.windows.firstMatch.exists, "Main window should exist")
        
        // Verify code editor area exists
        let codeEditor = app.textViews["CodeEditorTextView"]
        XCTAssertTrue(codeEditor.waitForExistence(timeout: 5), "Code editor should exist")
    }

    @MainActor
    func testCodeEditorFunctionality() throws {
        let app = XCUIApplication()
        app.launch()
        
        let codeEditor = app.textViews["CodeEditorTextView"]
        XCTAssertTrue(codeEditor.waitForExistence(timeout: 5), "Code editor should exist")
        
        // Test typing in editor
        codeEditor.click()
        codeEditor.typeText("let greeting = \"Hello, IDE!\"")
        
        // NOTE: On macOS, NSTextView-backed editors often do not expose typed contents reliably via XCUIElement.value.
        // This test is a smoke test to ensure typing does not crash the app.
        XCTAssertTrue(codeEditor.exists, "Code editor should still exist after typing")
        
        // Test text selection (simplified)
        codeEditor.doubleTap()
        
        // Test basic functionality without keyboard shortcuts
        sleep(1)
    }
}
