import XCTest
@testable import osx_ide

@MainActor
final class NativeTerminalEmbedderTests: XCTestCase {
    
    // MARK: - Mock Shell Manager
    
    private final class MockShellManager: ShellManaging {
        var delegate: ShellManagerDelegate?
        private(set) var sentInputs: [String] = []

        func start(in directory: URL?) {}

        func resize(rows: Int, columns: Int) {}

        func sendInput(_ text: String) {
            sentInputs.append(text)
        }

        func interrupt() {
            sentInputs.append("\u{03}")  // Ctrl-C
        }

        func terminate() {}
    }
    
    // MARK: - Helper Properties
    
    private var mockShell: MockShellManager!
    private var embedder: NativeTerminalEmbedder!
    
    // MARK: - Setup / Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        mockShell = MockShellManager()
        embedder = NativeTerminalEmbedder(shellManager: mockShell, eventBus: EventBus())
    }
    
    override func tearDown() async throws {
        embedder = nil
        mockShell = nil
        try await super.tearDown()
    }

    private func renderedString(from terminalOutput: String) -> String {
        let buffer = TerminalScreenBuffer(rows: 24, columns: 120)
        let textView = NSTextView()
        let renderer = TerminalScreenRenderer(textView: textView) { size, family in
            self.embedder.resolveFont(size: size, family: family) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }

        embedder.applyTerminalOutputToBuffer(terminalOutput, buffer: buffer)
        renderer.render(buffer, fontSize: embedder.fontSize, fontFamily: embedder.fontFamily)

        return textView.string
    }
    
    // MARK: - Basic Input Tests
    
    func testEnterSendsNewlineToShell() {
        let textView = NativeTerminalEmbedder.TerminalTextView()
        textView.inputDelegate = embedder
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(mockShell.sentInputs, ["\n"])
    }
    
    func testForwardTerminalInput() {
        embedder.forwardTerminalInput("ls -la")
        XCTAssertEqual(mockShell.sentInputs, ["ls -la"])
    }
    
    func testMultipleInputsAreAppended() {
        embedder.forwardTerminalInput("ls")
        embedder.forwardTerminalInput(" -la")
        embedder.forwardTerminalInput("\n")
        
        XCTAssertEqual(mockShell.sentInputs, ["ls", " -la", "\n"])
    }
    
    // MARK: - Command Handling Tests
    
    func testDeleteBackwardSendsBackspace() {
        let textView = NativeTerminalEmbedder.TerminalTextView()
        textView.inputDelegate = embedder
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        
        XCTAssertEqual(mockShell.sentInputs, ["\u{7F}"])
    }
    
    func testCancelOperationSendsInterrupt() {
        let textView = NativeTerminalEmbedder.TerminalTextView()
        textView.inputDelegate = embedder
        textView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        
        XCTAssertEqual(mockShell.sentInputs, ["\u{03}"])
    }
    
    func testInterruptSendsCtrlC() {
        embedder.forwardTerminalInput("some command")
        
        // Interrupt is called through shellManager
        mockShell.interrupt()
        
        XCTAssertEqual(mockShell.sentInputs.last, "\u{03}")
    }
    
    func testHandleTerminalCommandReturnsTrueForNewline() {
        let handled = embedder.handleTerminalCommand(#selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(handled)
        XCTAssertEqual(mockShell.sentInputs, ["\n"])
    }
    
    func testHandleTerminalCommandReturnsTrueForBackspace() {
        let handled = embedder.handleTerminalCommand(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertTrue(handled)
        XCTAssertEqual(mockShell.sentInputs, ["\u{7F}"])
    }
    
    func testHandleTerminalCommandReturnsTrueForCancel() {
        let handled = embedder.handleTerminalCommand(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertTrue(handled)
        XCTAssertEqual(mockShell.sentInputs, ["\u{03}"])
    }
    
    func testHandleTerminalCommandReturnsFalseForUnknown() {
        let handled = embedder.handleTerminalCommand(#selector(NSResponder.selectAll(_:)))
        XCTAssertFalse(handled)
        XCTAssertTrue(mockShell.sentInputs.isEmpty)
    }
    
    // MARK: - ANSI Parsing Tests
    
    func testParseSGRReset() {
        let output = renderedString(from: "\u{1B}[0m")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }
    
    func testParseSGRForegroundColors() {
        let output = renderedString(from: "\u{1B}[31mRed\u{1B}[0m")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Red")
    }
    
    func testParseMultipleSGRParameters() {
        let output = renderedString(from: "\u{1B}[1;31mBold Red\u{1B}[0m")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Bold Red")
    }
    
    func testParseOSCSequence() {
        // OSC sequence for setting window title
        let output = renderedString(from: "\u{1B}]0;My Title\u{07}Hello")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Hello")  // OSC should be skipped
    }
    
    func testParseOSCSequenceWithBELTerminator() {
        let output = renderedString(from: "\u{1B}]2;Status Message\u{07}World")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "World")
    }
    
    func testParseOSCSequenceWithStringTerminator() {
        // OSC with ST (\u{1B}\\) terminator
        let output = renderedString(from: "\u{1B}]0;Title\u{1B}\\Text")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Text")
    }
    
    func testParseCSISequenceCursorPosition() {
        // CSI H for cursor position - should move cursor but not render anything
        let output = renderedString(from: "\u{1B}[HTest")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Test")
    }
    
    func testParseCSISequenceWithParameters() {
        // CSI 10;20H for cursor position
        let output = renderedString(from: "\u{1B}[10;20HContent")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Content")
    }
    
    func testParseEraseInDisplay() {
        // CSI 2J - clear screen
        let output = renderedString(from: "\u{1B}[2JScreen Cleared")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Screen Cleared")
    }
    
    func testParseEraseInLine() {
        // CSI K - erase to end of line
        let output = renderedString(from: "\u{1B}[KLine Content")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Line Content")
    }
    
    func testParseAllANSIColors() {
        // Test all 8 basic ANSI colors
        let colorCodes = [30, 31, 32, 33, 34, 35, 36, 37]
        for code in colorCodes {
            let output = renderedString(from: "\u{1B}[\(code)mX")
            XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "X", "Failed for color code \(code)")
        }
    }
    
    func testParseBrightColors() {
        // Test bright color codes (90-97)
        let brightColorCodes = [90, 91, 92, 93, 94, 95, 96, 97]
        for code in brightColorCodes {
            let output = renderedString(from: "\u{1B}[\(code)mX")
            XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "X", "Failed for bright color code \(code)")
        }
    }
    
    func testParseBackgroundColors() {
        // Test background color codes (40-47)
        let bgCodes = [40, 41, 42, 43, 44, 45, 46, 47]
        for code in bgCodes {
            let output = renderedString(from: "\u{1B}[\(code)mX")
            XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "X", "Failed for background code \(code)")
        }
    }
    
    func testParseTextAttributes() {
        // Bold
        let boldOutput = renderedString(from: "\u{1B}[1mBold")
        XCTAssertEqual(boldOutput.trimmingCharacters(in: .whitespacesAndNewlines), "Bold")
        
        // Italic
        let italicOutput = renderedString(from: "\u{1B}[3mItalic")
        XCTAssertEqual(italicOutput.trimmingCharacters(in: .whitespacesAndNewlines), "Italic")
        
        // Underline
        let underlineOutput = renderedString(from: "\u{1B}[4mUnderline")
        XCTAssertEqual(underlineOutput.trimmingCharacters(in: .whitespacesAndNewlines), "Underline")
    }
    
    func testParseComplexANSISequence() {
        // Complex sequence with multiple attributes
        let output = renderedString(from: "\u{1B}[1;31;4mBold Red Underlined\u{1B}[0m Normal")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Bold Red Underlined Normal")
    }
    
    func testParseInvalidANSISequence() {
        // Invalid sequence should not crash
        let output = renderedString(from: "\u{1B}[ZZInvalid")
        // Should handle gracefully
        XCTAssertNotNil(output)
    }
    
    func testParseIncompleteANSISequence() {
        // Incomplete sequence at end of string
        let output = renderedString(from: "Text\u{1B}[")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Text")
    }
    
    // MARK: - Control Character Tests
    
    func testCarriageReturnOverwrites() {
        let output = renderedString(from: "Hello\rWorld")
        // "Hello" is written, then \r moves cursor to 0, then "World" overwrites "Hello"
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "World")
    }
    
    func testNewlineIsPreserved() {
        let output = renderedString(from: "Line1\nLine2")
        // Fixed-width rendering means each line has 120 chars (per renderedString helper)
        let lines = output.components(separatedBy: "\n")
        XCTAssertEqual(lines[0].trimmingCharacters(in: .whitespacesAndNewlines), "Line1")
        XCTAssertEqual(lines[1].trimmingCharacters(in: .whitespacesAndNewlines), "Line2")
    }
    
    func testTabIncrementsColumn() {
        let output = renderedString(from: "A\tB")
        XCTAssertTrue(output.contains("A"))
        XCTAssertTrue(output.contains("B"))
        // Tab stop at 8, so B should be at index 8
        let lines = output.components(separatedBy: "\n")
        let firstLine = lines[0]
        let indexA = firstLine.firstIndex(of: "A")!
        let indexB = firstLine.firstIndex(of: "B")!
        XCTAssertEqual(firstLine.distance(from: indexA, to: indexB), 8)
    }
    
    func testControlCharactersAreSkipped() {
        // Bell character (0x07) should be skipped in plain text
        let output = renderedString(from: "Hello\u{07}World")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "HelloWorld")
    }
    
    func testBackspaceMovesCursorBack_Overwrites() {
        let output = renderedString(from: "ABC\u{08}D")
        // ABC is written, cursor at 3. \u{08} moves to 2. D is written at 2, overwriting C.
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "ABD")
    }
    
    // MARK: - Font Resolution Tests
    
    func testResolveFontWithValidFamily() {
        let font = embedder.resolveFont(size: 14, family: "Menlo")
        XCTAssertEqual(font.pointSize, 14)
    }
    
    func testResolveFontWithInvalidFamilyFallsBack() {
        let font = embedder.resolveFont(size: 12, family: "NonExistentFont12345")
        XCTAssertEqual(font.pointSize, 12)
        // Should fall back to monospaced system font
    }
    
    func testResolveFontWithBoldWeight() {
        let font = embedder.resolveFont(size: 12, family: "SF Mono", weight: .bold)
        XCTAssertEqual(font.pointSize, 12)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
    }
    
    // MARK: - Embed Terminal Tests
    
    func testEmbedTerminalCreatesTextView() {
        let parentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        
        embedder.embedTerminal(in: parentView, directory: nil)
        
        XCTAssertNotNil(embedder.terminalView)
        XCTAssertTrue(parentView.subviews.contains { $0 is NSScrollView })
    }
    
    func testEmbedTerminalWithCustomFont() {
        let parentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        
        embedder.embedTerminal(in: parentView, directory: nil, fontSize: 16, fontFamily: "Menlo")
        
        XCTAssertNotNil(embedder.terminalView)
        XCTAssertEqual(embedder.fontSize, 16)
        XCTAssertEqual(embedder.fontFamily, "Menlo")
    }
    
    // MARK: - Update Font Tests
    
    func testUpdateFont() {
        let parentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        embedder.embedTerminal(in: parentView, directory: nil)
        
        embedder.updateFont(size: 18, family: "Monaco")
        
        XCTAssertEqual(embedder.fontSize, 18)
        XCTAssertEqual(embedder.fontFamily, "Monaco")
        XCTAssertNotNil(embedder.terminalView?.font)
    }
    
    // MARK: - Focus Tests
    
    func testFocusTerminal() {
        let parentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        embedder.embedTerminal(in: parentView, directory: nil)
        
        // Should not crash when focusing
        embedder.focusTerminal()
        
        // Terminal view should exist
        XCTAssertNotNil(embedder.terminalView)
    }
    
    // MARK: - Clear Terminal Tests
    
    func testClearTerminal() {
        let parentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        embedder.embedTerminal(in: parentView, directory: nil)
        
        embedder.terminalView?.string = "Some content"
        
        embedder.clearTerminal()
        
        XCTAssertEqual(embedder.terminalView?.string.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }
    
    // MARK: - Cleanup Tests
    
    func testRemoveEmbedding() {
        let parentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        embedder.embedTerminal(in: parentView, directory: nil)
        
        embedder.removeEmbedding()
        
        XCTAssertNil(embedder.terminalView)
    }
    
    func testCleanupSetsFlag() {
        embedder.cleanup()
        
        XCTAssertTrue(embedder.isCleaningUp)
    }
    
    // MARK: - ANSI Color Helper Tests
    
    func testAnsiColorMapping() {
        // Test that ANSI color codes map to expected colors
        let black = embedder.ansiColor(0)
        let red = embedder.ansiColor(1)
        let green = embedder.ansiColor(2)
        let yellow = embedder.ansiColor(3)
        let blue = embedder.ansiColor(4)
        let magenta = embedder.ansiColor(5)
        let cyan = embedder.ansiColor(6)
        let white = embedder.ansiColor(7)
        
        XCTAssertEqual(black, NSColor.black)
        XCTAssertEqual(red, NSColor.red)
        XCTAssertEqual(green, NSColor.green)
        XCTAssertEqual(yellow, NSColor.yellow)
        XCTAssertEqual(blue, NSColor.blue)
        XCTAssertEqual(magenta, NSColor.magenta)
        XCTAssertEqual(cyan, NSColor.cyan)
        XCTAssertEqual(white, NSColor.white)
    }
    
    func testAnsiColorInvalidCodeReturnsGreen() {
        let color = embedder.ansiColor(99)
        XCTAssertEqual(color, NSColor.green)
    }
    
    func testAnsiBrightColorMapping() {
        // Test bright color codes
        let brightBlack = embedder.ansiBrightColor(0)
        let brightRed = embedder.ansiBrightColor(1)
        let brightWhite = embedder.ansiBrightColor(7)
        
        XCTAssertNotNil(brightBlack)
        XCTAssertNotNil(brightRed)
        XCTAssertNotNil(brightWhite)
    }
    
    func testAnsiBrightColorInvalidCodeReturnsGreen() {
        let color = embedder.ansiBrightColor(99)
        XCTAssertEqual(color, NSColor.green)
    }
    
    func testPlainTextOnly() {
        let output = renderedString(from: "Hello, World!")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Hello, World!")
    }
    
    func testMultipleConsecutiveANSISequences() {
        let output = renderedString(from: "\u{1B}[1m\u{1B}[31m\u{1B}[4mText")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Text")
    }
    
    func testANSIAtEndOfString() {
        let output = renderedString(from: "Text\u{1B}[0m")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "Text")
    }
}
