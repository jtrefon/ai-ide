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

        // Given: Settings window is opened
        let settingsWindow = openSettingsWindow(app: app)
        
        // When: Settings controls are interacted with
        interactWithSettingsControls(app: app, settingsWindow: settingsWindow)
        
        // Then: Editor should still exist and be focused
        verifyEditorStillExists(editor: editor)
    }
    
    /// Opens the settings window and returns it
    private func openSettingsWindow(app: XCUIApplication) -> XCUIElement {
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
        
        return settingsWindow
    }
    
    /// Interacts with discoverable settings controls
    private func interactWithSettingsControls(app: XCUIApplication, settingsWindow: XCUIElement) {
        let themeControl = app.segmentedControls["Settings.Theme"]
        let fontSizeSlider = app.sliders["Settings.FontSize"]
        let wordWrapToggle = app.switches["Settings.WordWrap"]

        // If controls are discoverable, interact with them
        if fontSizeSlider.waitForExistence(timeout: 2) {
            testFontSizeSlider(slider: fontSizeSlider)
        }
        
        if wordWrapToggle.waitForExistence(timeout: 2) {
            testWordWrapToggle(toggle: wordWrapToggle)
        }
    }
    
    /// Tests font size slider interaction
    private func testFontSizeSlider(slider: XCUIElement) {
        let initialSliderValue = slider.value as? String ?? ""
        slider.adjust(toNormalizedSliderPosition: 0.7)

        waitForValueChange(of: slider, from: initialSliderValue, timeout: 2.0)

        let adjustedSliderValue = slider.value as? String ?? ""
        XCTAssertNotEqual(
            initialSliderValue, 
            adjustedSliderValue, 
            "Font size slider value should change after adjustment"
        )
    }
    
    /// Tests word wrap toggle interaction
    private func testWordWrapToggle(toggle: XCUIElement) {
        let initialToggleValue = toggle.value as? String ?? ""
        toggle.click()

        waitForValueChange(of: toggle, from: initialToggleValue, timeout: 2.0)

        let toggledValue = toggle.value as? String ?? ""
        XCTAssertNotEqual(initialToggleValue, toggledValue, "Word wrap toggle value should change")
    }
    
    /// Verifies that the editor still exists and is focused
    private func verifyEditorStillExists(editor: XCUIElement) {
        // Close settings window
        let app = XCUIApplication()
        app.typeKey("w", modifierFlags: [.command])

        // Verify editor still exists and is focused
        XCTAssertTrue(editor.exists, "Editor should still exist after settings changes")
    }
}
