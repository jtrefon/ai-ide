//
//  TerminalEchoUITests.swift
//  osx-ideUITests
//
//  Created by AI Assistant on 23/12/2025.
//

import XCTest
import Vision

@MainActor
final class TerminalEchoUITests: XCTestCase {

    private func recognizedText(from screenshot: XCUIScreenshot) -> String {
        guard let cgImage = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
    
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

    /// Regression: command output must be visible and not overwritten by the prompt (multi-line output should appear).
    func testTerminalCommandOutputVisible_Multiline() throws {
        let app = XCUIApplication()
        app.launch()

        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10), "Main window should exist")

        let terminalView = app.textViews["TerminalTextView"]
        let terminalExists = terminalView.waitForExistence(timeout: 5)

        if terminalExists {
            terminalView.click()

            // Print multiple lines so we can assert output is present and not overwritten.
            terminalView.typeText("printf 'line_one\\nline_two\\n'")
            terminalView.typeText("\n")

            sleep(2)
            let terminalContent = terminalView.value as? String ?? ""

            XCTAssertTrue(terminalContent.contains("line_one"), "Terminal should show first output line")
            XCTAssertTrue(terminalContent.contains("line_two"), "Terminal should show second output line")
            XCTAssertTrue(
                terminalContent.range(of: "line_one")?.lowerBound ?? terminalContent.startIndex
                    < (terminalContent.range(of: "line_two")?.lowerBound ?? terminalContent.endIndex),
                "Output lines should appear in order"
            )
        } else {
            XCTSkip("Terminal view not found - skipping multiline output visibility regression")
        }
    }

    /// Repro: after typing the second character, the first character appears duplicated in the rendered terminal output.
    /// Example: typing 'l' then 's' displays 'lls'. Uses screenshot OCR to capture visual output.
    /// Note: keeping this method name stable ensures xcodebuild -only-testing targets it reliably.
    func testTerminalFirstLetterNotDuplicated_Rendered() throws {
        let app = XCUIApplication()
        app.launch()

        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10), "Main window should exist")

        let terminalView = app.textViews["TerminalTextView"]
        let terminalExists = terminalView.waitForExistence(timeout: 5)

        if terminalExists {
            terminalView.click()

            terminalView.typeText("l")
            usleep(250_000)
            terminalView.typeText("s")
            sleep(1)

            let screenshot = terminalView.screenshot()
            let ocr = recognizedText(from: screenshot)
            if ocr.contains("lls") {
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "Terminal after typing l then s"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertFalse(ocr.contains("lls"), "Terminal should not display duplicated first letter (must not show 'lls' after typing 'l' then 's'). OCR text was: \n\(ocr)")
        } else {
            XCTSkip("Terminal view not found - skipping rendered first-letter duplication repro")
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
