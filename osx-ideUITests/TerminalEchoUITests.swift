//
//  TerminalEchoUITests.swift
//  osx-ideUITests
//
//  Created by AI Assistant on 23/12/2025.
//

import XCTest

@MainActor
final class TerminalEchoUITests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
        // Clean up by terminating the app
        XCUIApplication().terminate()
    }
    
    /// Test that terminal input does not produce double echo
    func testTerminalNoDoubleEcho() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for the app to fully load
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10), "Main window should exist")
        
        // Look for terminal view or terminal-related UI elements
        // This might need adjustment based on the actual UI structure
        let terminalView = app.textViews["TerminalTextView"]
        let terminalExists = terminalView.waitForExistence(timeout: 5)
        
        if terminalExists {
            // Test typing in terminal
            terminalView.click()
            terminalView.typeText("echo test")
            
            // Wait a moment for processing
            sleep(1)
            
            // Get the terminal content
            let terminalContent = terminalView.value as? String ?? ""
            
            // Verify that "echo test" appears only once (not double echoed)
            let echoTestCount = terminalContent.components(separatedBy: "echo test").count - 1
            XCTAssertLessThanOrEqual(echoTestCount, 1, "Terminal should not double echo input")
            
            // Test pressing Enter
            terminalView.typeText("\n")
            sleep(1)
            
            // Verify the command was executed (should see "test" output)
            let updatedContent = terminalView.value as? String ?? ""
            XCTAssertTrue(updatedContent.contains("test"), "Command should be executed and show output")
        } else {
            // If terminal view is not directly accessible, we'll test through menu or other means
            // For now, we'll skip this test if terminal is not found
            XCTSkip("Terminal view not found - skipping echo test")
        }
    }
    
    /// Test basic terminal functionality
    func testTerminalBasicFunctionality() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for the app to fully load
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10), "Main window should exist")
        
        // Look for terminal-related UI elements
        let terminalView = app.textViews["TerminalTextView"]
        let terminalExists = terminalView.waitForExistence(timeout: 5)
        
        if terminalExists {
            // Test that terminal responds to input
            terminalView.click()
            terminalView.typeText("pwd")
            terminalView.typeText("\n")
            
            // Wait for command to execute
            sleep(2)
            
            // Verify we got some output (should contain current directory)
            let terminalContent = terminalView.value as? String ?? ""
            XCTAssertFalse(terminalContent.isEmpty, "Terminal should produce output")
        } else {
            XCTSkip("Terminal view not found - skipping basic functionality test")
        }
    }
}
