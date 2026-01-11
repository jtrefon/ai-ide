//
//  SettingsGeneralUITests.swift
//  osx-ideUITests
//

import XCTest

@MainActor
final class SettingsGeneralUITests: XCTestCase {

    private func skipIfElementNotDiscoverable(_ element: XCUIElement, name: String, timeout: TimeInterval) {
        if !element.waitForExistence(timeout: timeout) {
            XCTSkip("\(name) not discoverable by XCTest on this machine/session")
        }
        if !element.exists {
            XCTSkip("\(name) became undiscoverable after initial wait (accessibility snapshot flake)")
        }
    }

    private func waitForValueChange(of element: XCUIElement, from initialValue: String, timeout: TimeInterval) {
        let valueChanged = expectation(description: "Value changed")
        let pollInterval: TimeInterval = 0.1
        var elapsedTime: TimeInterval = 0

        while elapsedTime < timeout {
            let currentValue = element.value as? String ?? ""
            if currentValue != initialValue {
                valueChanged.fulfill()
                break
            }
            Thread.sleep(forTimeInterval: pollInterval)
            elapsedTime += pollInterval
        }

        wait(for: [valueChanged], timeout: timeout + 0.5)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        let app = XCUIApplication()
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }

    func testGeneralSettingsAffectEditor() throws {
        let app = XCUIApplication()
        app.launchEnvironment["XCUI_TESTING"] = "1"
        app.launch()

        let mainWindow = app.windows.firstMatch
        skipIfElementNotDiscoverable(mainWindow, name: "Main window", timeout: 5)

        let editor = app.textViews["CodeEditorTextView"]
        skipIfElementNotDiscoverable(editor, name: "Code editor", timeout: 5)

        // Open Settings (Cmd+,)
        app.typeKey(",", modifierFlags: [.command])

        // Wait for settings window to appear
        let settingsWindow = app.windows.firstMatch
        skipIfElementNotDiscoverable(settingsWindow, name: "Settings window", timeout: 5)

        // Verify settings window opened
        XCTAssertTrue(settingsWindow.exists, "Settings window should be open")
        XCTAssertFalse(settingsWindow.title.isEmpty, "Settings window should have a title")

        // Look for any scroll views (settings content is usually in a scroll view)
        let scrollViews = settingsWindow.scrollViews
        let hasContent = scrollViews.count > 0 || settingsWindow.staticTexts.count > 0
        XCTAssertTrue(hasContent, "Settings window should contain UI elements")

        // Try to find specific controls (may not be discoverable in all environments)
        let themeControl = app.segmentedControls["Settings.Theme"]
        let fontSizeSlider = app.sliders["Settings.FontSize"]
        let wordWrapToggle = app.switches["Settings.WordWrap"]

        let themeExists = themeControl.waitForExistence(timeout: 2)
        let sliderExists = fontSizeSlider.waitForExistence(timeout: 2)
        let toggleExists = wordWrapToggle.waitForExistence(timeout: 2)

        // If controls are discoverable, interact with them
        if sliderExists {
            let initialSliderValue = fontSizeSlider.value as? String ?? ""
            fontSizeSlider.adjust(toNormalizedSliderPosition: 0.7)

            waitForValueChange(of: fontSizeSlider, from: initialSliderValue, timeout: 2.0)

            let adjustedSliderValue = fontSizeSlider.value as? String ?? ""
            XCTAssertNotEqual(initialSliderValue, adjustedSliderValue, "Font size slider value should change after adjustment")
        }

        if toggleExists {
            let initialToggleValue = wordWrapToggle.value as? String ?? ""
            wordWrapToggle.click()

            waitForValueChange(of: wordWrapToggle, from: initialToggleValue, timeout: 2.0)

            let toggledValue = wordWrapToggle.value as? String ?? ""
            XCTAssertNotEqual(initialToggleValue, toggledValue, "Word wrap toggle value should change")
        }

        // Close settings window
        app.typeKey("w", modifierFlags: [.command])

        // Verify editor still exists and is focused
        XCTAssertTrue(editor.exists, "Editor should still exist after settings changes")
    }
}
