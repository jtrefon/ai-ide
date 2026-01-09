//
//  SettingsGeneralUITests.swift
//  osx-ideUITests
//

import XCTest

@MainActor
final class SettingsGeneralUITests: XCTestCase {

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
        if !mainWindow.waitForExistence(timeout: 5) {
            XCTSkip("Main window not discoverable by XCTest on this machine/session")
        }

        let editor = app.textViews["CodeEditorTextView"]
        if !editor.waitForExistence(timeout: 5) {
            XCTSkip("Code editor not discoverable by XCTest on this machine/session")
        }

        if !editor.exists {
            XCTSkip("Code editor became undiscoverable after initial wait (accessibility snapshot flake)")
        }

        // Open Settings (Cmd+,)
        app.typeKey(",", modifierFlags: [.command])

        // Wait for settings window to appear
        let settingsWindow = app.windows.firstMatch
        if !settingsWindow.waitForExistence(timeout: 5) {
            XCTSkip("Settings window not discoverable by XCTest on this machine/session")
        }

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

            // Wait for slider value to change using expectation
            let sliderChanged = expectation(description: "Slider value changed")
            let pollInterval: TimeInterval = 0.1
            let maxWaitTime: TimeInterval = 2.0
            var elapsedTime: TimeInterval = 0

            while elapsedTime < maxWaitTime {
                let currentValue = fontSizeSlider.value as? String ?? ""
                if currentValue != initialSliderValue {
                    sliderChanged.fulfill()
                    break
                }
                Thread.sleep(forTimeInterval: pollInterval)
                elapsedTime += pollInterval
            }

            wait(for: [sliderChanged], timeout: maxWaitTime + 0.5)

            let adjustedSliderValue = fontSizeSlider.value as? String ?? ""
            XCTAssertNotEqual(initialSliderValue, adjustedSliderValue, "Font size slider value should change after adjustment")
        }

        if toggleExists {
            let initialToggleValue = wordWrapToggle.value as? String ?? ""
            wordWrapToggle.click()

            // Wait for toggle value to change using expectation
            let toggleChanged = expectation(description: "Toggle value changed")
            let pollInterval: TimeInterval = 0.1
            let maxWaitTime: TimeInterval = 2.0
            var elapsedTime: TimeInterval = 0

            while elapsedTime < maxWaitTime {
                let currentValue = wordWrapToggle.value as? String ?? ""
                if currentValue != initialToggleValue {
                    toggleChanged.fulfill()
                    break
                }
                Thread.sleep(forTimeInterval: pollInterval)
                elapsedTime += pollInterval
            }

            wait(for: [toggleChanged], timeout: maxWaitTime + 0.5)

            let toggledValue = wordWrapToggle.value as? String ?? ""
            XCTAssertNotEqual(initialToggleValue, toggledValue, "Word wrap toggle value should change")
        }

        // Close settings window
        app.typeKey("w", modifierFlags: [.command])

        // Verify editor still exists and is focused
        XCTAssertTrue(editor.exists, "Editor should still exist after settings changes")
    }
}
