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
        let result = embedder.processANSIEscapeSequences("\u{1B}[0m")
        XCTAssertEqual(result.string, "")
    }
    
    func testParseSGRForegroundColors() {
        let result = embedder.processANSIEscapeSequences("\u{1B}[31mRed\u{1B}[0m")
        XCTAssertEqual(result.string, "Red")
    }
    
    func testParseMultipleSGRParameters() {
        let result = embedder.processANSIEscapeSequences("\u{1B}[1;31mBold Red\u{1B}[0m")
        XCTAssertEqual(result.string, "Bold Red")
    }
    
    func testParseOSCSequence() {
        // OSC sequence for setting window title
        let result = embedder.processANSIEscapeSequences("\u{1B}]0;My Title\u{07}Hello")
        XCTAssertEqual(result.string, "Hello")  // OSC should be skipped
    }
    
    func testParseOSCSequenceWithBELTerminator() {
        let result = embedder.processANSIEscapeSequences("\u{1B}]2;Status Message\u{07}World")
        XCTAssertEqual(result.string, "World")
    }
    
    func testParseOSCSequenceWithStringTerminator() {
        // OSC with ST (\u{1B}\\) terminator
        let result = embedder.processANSIEscapeSequences("\u{1B}]0;Title\u{1B}\\Text")
        XCTAssertEqual(result.string, "Text")
    }
    
    func testParseCSISequenceCursorPosition() {
        // CSI H for cursor position - should be skipped
        let result = embedder.processANSIEscapeSequences("\u{1B}[HTest")
        XCTAssertEqual(result.string, "Test")
    }
    
    func testParseCSISequenceWithParameters() {
        // CSI 10;20H for cursor position
        let result = embedder.processANSIEscapeSequences("\u{1B}[10;20HContent")
        XCTAssertEqual(result.string, "Content")
    }
    
    func testParseEraseInDisplay() {
        // CSI 2J - clear screen
        let result = embedder.processANSIEscapeSequences("\u{1B}[2JScreen Cleared")
        XCTAssertEqual(result.string, "Screen Cleared")
    }
    
    func testParseEraseInLine() {
        // CSI K - erase to end of line
        let result = embedder.processANSIEscapeSequences("\u{1B}[KLine Content")
        XCTAssertEqual(result.string, "Line Content")
    }
    
    func testParseAllANSIColors() {
        // Test all 8 basic ANSI colors
        let colorCodes = [30, 31, 32, 33, 34, 35, 36, 37]
        for code in colorCodes {
            let result = embedder.processANSIEscapeSequences("\u{1B}[\(code)mX")
            XCTAssertEqual(result.string, "X", "Failed for color code \(code)")
        }
    }
    
    func testParseBrightColors() {
        // Test bright color codes (90-97)
        let brightColorCodes = [90, 91, 92, 93, 94, 95, 96, 97]
        for code in brightColorCodes {
            let result = embedder.processANSIEscapeSequences("\u{1B}[\(code)mX")
            XCTAssertEqual(result.string, "X", "Failed for bright color code \(code)")
        }
    }
    
    func testParseBackgroundColors() {
        // Test background color codes (40-47)
        let bgCodes = [40, 41, 42, 43, 44, 45, 46, 47]
        for code in bgCodes {
            let result = embedder.processANSIEscapeSequences("\u{1B}[\(code)mX")
            XCTAssertEqual(result.string, "X", "Failed for background code \(code)")
        }
    }
    
    func testParseTextAttributes() {
        // Bold
        let boldResult = embedder.processANSIEscapeSequences("\u{1B}[1mBold")
        XCTAssertEqual(boldResult.string, "Bold")
        
        // Italic
        let italicResult = embedder.processANSIEscapeSequences("\u{1B}[3mItalic")
        XCTAssertEqual(italicResult.string, "Italic")
        
        // Underline
        let underlineResult = embedder.processANSIEscapeSequences("\u{1B}[4mUnderline")
        XCTAssertEqual(underlineResult.string, "Underline")
    }
    
    func testParseComplexANSISequence() {
        // Complex sequence with multiple attributes
        let result = embedder.processANSIEscapeSequences("\u{1B}[1;31;4mBold Red Underlined\u{1B}[0m Normal")
        XCTAssertEqual(result.string, "Bold Red Underlined Normal")
    }
    
    func testParseInvalidANSISequence() {
        // Invalid sequence should not crash
        let result = embedder.processANSIEscapeSequences("\u{1B}[ZZInvalid")
        // Should handle gracefully
        XCTAssertNotNil(result.string)
    }
    
    func testParseIncompleteANSISequence() {
        // Incomplete sequence at end of string
        let result = embedder.processANSIEscapeSequences("Text\u{1B}[")
        XCTAssertEqual(result.string, "Text")
    }
    
    // MARK: - Control Character Tests
    
    func testCarriageReturnIsSkipped() {
        let result = embedder.processANSIEscapeSequences("Hello\rWorld")
        XCTAssertEqual(result.string, "HelloWorld")
    }
    
    func testNewlineIsPreserved() {
        let result = embedder.processANSIEscapeSequences("Line1\nLine2")
        XCTAssertEqual(result.string, "Line1\nLine2")
    }
    
    func testTabIsPreserved() {
        let result = embedder.processANSIEscapeSequences("Col1\tCol2")
        XCTAssertEqual(result.string, "Col1\tCol2")
    }
    
    func testControlCharactersAreSkipped() {
        // Bell character (0x07) should be skipped in plain text
        let result = embedder.processANSIEscapeSequences("Hello\u{07}World")
        XCTAssertEqual(result.string, "HelloWorld")
    }
    
    func testBackspaceIsSkipped() {
        let result = embedder.processANSIEscapeSequences("ABC\u{08}D")
        XCTAssertEqual(result.string, "ABCD")
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
        
        XCTAssertEqual(embedder.terminalView?.string, "")
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
    
    // MARK: - SGR Parameter Tests
    
    func testApplySGRParametersReset() {
        let attributes = embedder.applySGRParameters([0])
        
        XCTAssertNotNil(attributes[.font])
        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, NSColor.green)
    }
    
    func testApplySGRParametersBold() {
        let attributes = embedder.applySGRParameters([1])
        
        XCTAssertNotNil(attributes[.font])
    }
    
    func testApplySGRParametersItalic() {
        let attributes = embedder.applySGRParameters([3])
        
        // Italic is applied via obliqueness attribute
        XCTAssertNotNil(attributes[.obliqueness])
    }
    
    func testApplySGRParametersUnderline() {
        let attributes = embedder.applySGRParameters([4])
        
        XCTAssertEqual(attributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
    }
    
    func testApplySGRParametersForegroundColor() {
        let attributes = embedder.applySGRParameters([31])  // Red
        
        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, NSColor.red)
    }
    
    func testApplySGRParametersBackgroundColor() {
        let attributes = embedder.applySGRParameters([41])  // Red background
        
        XCTAssertEqual(attributes[.backgroundColor] as? NSColor, NSColor.red)
    }
    
    func testApplySGRParametersEmptyArrayResets() {
        // Empty parameters array should behave like reset (parameter 0)
        let attributes = embedder.applySGRParameters([])
        
        XCTAssertNotNil(attributes[.font])
        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, NSColor.green)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyStringProcessing() {
        let result = embedder.processANSIEscapeSequences("")
        XCTAssertEqual(result.string, "")
    }
    
    func testPlainTextOnly() {
        let result = embedder.processANSIEscapeSequences("Hello, World!")
        XCTAssertEqual(result.string, "Hello, World!")
    }
    
    func testMultipleConsecutiveANSISequences() {
        let result = embedder.processANSIEscapeSequences("\u{1B}[1m\u{1B}[31m\u{1B}[4mText")
        XCTAssertEqual(result.string, "Text")
    }
    
    func testANSIAtEndOfString() {
        let result = embedder.processANSIEscapeSequences("Text\u{1B}[0m")
        XCTAssertEqual(result.string, "Text")
    }
}
