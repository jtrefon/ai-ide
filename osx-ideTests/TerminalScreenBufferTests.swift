import XCTest
@testable import osx_ide

@MainActor
final class TerminalScreenBufferTests: XCTestCase {
    
    var buffer: TerminalScreenBuffer!
    
    override func setUp() async throws {
        try await super.setUp()
        buffer = TerminalScreenBuffer(rows: 24, columns: 80)
    }
    
    override func tearDown() async throws {
        buffer = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertEqual(buffer.rows, 24)
        XCTAssertEqual(buffer.columns, 80)
        XCTAssertEqual(buffer.cursorRow, 0)
        XCTAssertEqual(buffer.cursorColumn, 0)
    }
    
    func testInitializationWithDefaultParameters() {
        let defaultBuffer = TerminalScreenBuffer()
        XCTAssertEqual(defaultBuffer.rows, 24)
        XCTAssertEqual(defaultBuffer.columns, 80)
    }
    
    func testInitialGridIsEmpty() {
        for row in 0..<buffer.rows {
            for col in 0..<buffer.columns {
                XCTAssertEqual(buffer.grid[row][col].character, " ", "Cell at (\(row), \(col)) should be empty")
            }
        }
    }
    
    // MARK: - Character Output Tests
    
    func testPutCharacter() {
        buffer.putCharacter("A")
        XCTAssertEqual(buffer.cursorColumn, 1)
        XCTAssertEqual(buffer.grid[0][0].character, "A")
    }
    
    func testPutCharacterAdvancesColumn() {
        buffer.putCharacter("H")
        buffer.putCharacter("i")
        XCTAssertEqual(buffer.cursorColumn, 2)
        XCTAssertEqual(buffer.grid[0][0].character, "H")
        XCTAssertEqual(buffer.grid[0][1].character, "i")
    }
    
    func testPutCharacterWrapsAtLineEnd() {
        for _ in 0..<80 {
            buffer.putCharacter("X")
        }
        XCTAssertEqual(buffer.cursorRow, 1)
        XCTAssertEqual(buffer.cursorColumn, 0)
    }
    
    func testPutCharacterMultipleWraps() {
        // Write 160 characters (2 full lines)
        for i in 0..<160 {
            buffer.putCharacter(Character("\(i % 10)"))
        }
        XCTAssertEqual(buffer.cursorRow, 2)
        XCTAssertEqual(buffer.cursorColumn, 0)
    }
    
    func testPutCharacterAtLastColumn() {
        buffer.moveCursor(row: 0, column: 79)
        buffer.putCharacter("Z")
        XCTAssertEqual(buffer.cursorRow, 1)
        XCTAssertEqual(buffer.cursorColumn, 0)
        XCTAssertEqual(buffer.grid[0][79].character, "Z")
    }
    
    // MARK: - Cursor Movement Tests
    
    func testMoveCursor() {
        buffer.moveCursor(row: 5, column: 10)
        XCTAssertEqual(buffer.cursorRow, 5)
        XCTAssertEqual(buffer.cursorColumn, 10)
    }
    
    func testMoveCursorClampsToValidRange() {
        buffer.moveCursor(row: 100, column: 100)
        XCTAssertEqual(buffer.cursorRow, 23)  // rows - 1
        XCTAssertEqual(buffer.cursorColumn, 79)  // columns - 1
    }
    
    func testMoveCursorClampsNegativeValues() {
        buffer.moveCursor(row: -5, column: -10)
        XCTAssertEqual(buffer.cursorRow, 0)
        XCTAssertEqual(buffer.cursorColumn, 0)
    }
    
    func testMoveCursorRelative() {
        buffer.moveCursor(row: 5, column: 10)
        buffer.moveCursorRelative(rowDelta: 2, columnDelta: 5)
        XCTAssertEqual(buffer.cursorRow, 7)
        XCTAssertEqual(buffer.cursorColumn, 15)
    }
    
    func testMoveCursorRelativeNegative() {
        buffer.moveCursor(row: 10, column: 20)
        buffer.moveCursorRelative(rowDelta: -3, columnDelta: -5)
        XCTAssertEqual(buffer.cursorRow, 7)
        XCTAssertEqual(buffer.cursorColumn, 15)
    }
    
    func testMoveCursorRelativeClampsToValidRange() {
        buffer.moveCursor(row: 5, column: 10)
        buffer.moveCursorRelative(rowDelta: -10, columnDelta: -20)
        XCTAssertEqual(buffer.cursorRow, 0)
        XCTAssertEqual(buffer.cursorColumn, 0)
    }
    
    func testCarriageReturn() {
        buffer.moveCursor(row: 5, column: 50)
        buffer.carriageReturn()
        XCTAssertEqual(buffer.cursorColumn, 0)
        XCTAssertEqual(buffer.cursorRow, 5)  // Row unchanged
    }
    
    func testNewline() {
        buffer.moveCursor(row: 5, column: 50)
        buffer.newline()
        XCTAssertEqual(buffer.cursorRow, 6)
        XCTAssertEqual(buffer.cursorColumn, 0)  // Column reset to 0
    }
    
    func testBackspace() {
        buffer.moveCursor(row: 5, column: 50)
        buffer.backspace()
        XCTAssertEqual(buffer.cursorColumn, 49)
    }
    
    func testBackspaceStopsAtZero() {
        buffer.backspace()
        XCTAssertEqual(buffer.cursorColumn, 0)
    }
    
    func testBackspaceDoesNotAffectRow() {
        buffer.moveCursor(row: 5, column: 0)
        buffer.backspace()
        XCTAssertEqual(buffer.cursorRow, 5)
        XCTAssertEqual(buffer.cursorColumn, 0)
    }
    
    func testTab() {
        buffer.putCharacter("A")
        buffer.tab()
        XCTAssertEqual(buffer.cursorColumn, 8)
    }
    
    func testTabToNextStop() {
        buffer.moveCursor(row: 0, column: 10)
        buffer.tab()
        XCTAssertEqual(buffer.cursorColumn, 16)
    }
    
    func testTabAtColumnZero() {
        buffer.tab()
        XCTAssertEqual(buffer.cursorColumn, 8)
    }
    
    func testTabClampsAtLastColumn() {
        buffer.moveCursor(row: 0, column: 78)
        buffer.tab()
        XCTAssertEqual(buffer.cursorColumn, 79)  // Clamped to columns - 1
    }
    
    func testTabStopsAtEveryEightColumns() {
        // Test multiple tab stops
        buffer.tab()
        XCTAssertEqual(buffer.cursorColumn, 8)
        buffer.tab()
        XCTAssertEqual(buffer.cursorColumn, 16)
        buffer.tab()
        XCTAssertEqual(buffer.cursorColumn, 24)
        buffer.tab()
        XCTAssertEqual(buffer.cursorColumn, 32)
    }
    
    // MARK: - Erase Tests
    
    func testEraseToEndOfLine() {
        // Fill first 10 cells with characters using putCharacter
        buffer.moveCursor(row: 0, column: 0)
        for i in 0..<10 {
            buffer.putCharacter(Character("\(i)"))
        }
        // Reset and fill rest of line with spaces to simulate a clean line
        buffer.moveCursor(row: 0, column: 5)
        buffer.eraseToEndOfLine()
        
        // First 5 characters should remain
        XCTAssertEqual(buffer.grid[0][0].character, "0")
        XCTAssertEqual(buffer.grid[0][4].character, "4")
        
        // Rest should be empty
        XCTAssertEqual(buffer.grid[0][5].character, " ")
        XCTAssertEqual(buffer.grid[0][9].character, " ")
    }
    
    func testEraseToStartOfLine() {
        // Fill first 10 cells with characters
        buffer.moveCursor(row: 0, column: 0)
        for i in 0..<10 {
            buffer.putCharacter(Character("\(i)"))
        }
        buffer.moveCursor(row: 0, column: 5)
        buffer.eraseToStartOfLine()
        
        // First 6 characters (0-5 inclusive) should be cleared
        XCTAssertEqual(buffer.grid[0][0].character, " ")
        XCTAssertEqual(buffer.grid[0][5].character, " ")
        
        // Rest should remain
        XCTAssertEqual(buffer.grid[0][6].character, "6")
        XCTAssertEqual(buffer.grid[0][9].character, "9")
    }
    
    func testEraseLine() {
        // Fill first 10 cells with characters
        buffer.moveCursor(row: 0, column: 0)
        for i in 0..<10 {
            buffer.putCharacter(Character("\(i)"))
        }
        buffer.eraseLine()
        
        for i in 0..<10 {
            XCTAssertEqual(buffer.grid[0][i].character, " ")
        }
    }
    
    func testEraseScreen() {
        // Fill some cells using putCharacter
        buffer.moveCursor(row: 0, column: 0)
        buffer.putCharacter("A")
        buffer.moveCursor(row: 10, column: 10)
        buffer.putCharacter("B")
        
        buffer.eraseScreen()
        
        XCTAssertEqual(buffer.grid[0][0].character, " ")
        XCTAssertEqual(buffer.grid[10][10].character, " ")
    }
    
    func testEraseToEndOfScreen() {
        // Fill multiple cells
        buffer.moveCursor(row: 0, column: 0)
        buffer.putCharacter("A")
        buffer.moveCursor(row: 5, column: 5)
        buffer.putCharacter("B")
        buffer.moveCursor(row: 10, column: 10)
        buffer.putCharacter("C")
        
        buffer.moveCursor(row: 5, column: 5)
        buffer.eraseToEndOfScreen()
        
        // Content before cursor should remain
        XCTAssertEqual(buffer.grid[0][0].character, "A")
        
        // Content at and after cursor should be cleared
        XCTAssertEqual(buffer.grid[5][5].character, " ")
        XCTAssertEqual(buffer.grid[10][10].character, " ")
    }
    
    func testEraseToStartOfScreen() {
        // Fill multiple cells
        buffer.moveCursor(row: 0, column: 0)
        buffer.putCharacter("A")
        buffer.moveCursor(row: 5, column: 5)
        buffer.putCharacter("B")
        buffer.moveCursor(row: 10, column: 10)
        buffer.putCharacter("C")
        
        buffer.moveCursor(row: 5, column: 5)
        buffer.eraseToStartOfScreen()
        
        // Content before and at cursor should be cleared
        XCTAssertEqual(buffer.grid[0][0].character, " ")
        XCTAssertEqual(buffer.grid[5][5].character, " ")
        
        // Content after cursor should remain
        XCTAssertEqual(buffer.grid[10][10].character, "C")
    }
    
    func testClear() {
        buffer.putCharacter("A")
        buffer.moveCursor(row: 10, column: 10)
        buffer.putCharacter("B")
        
        buffer.clear()
        
        XCTAssertEqual(buffer.grid[0][0].character, " ")
        XCTAssertEqual(buffer.grid[10][10].character, " ")
        XCTAssertEqual(buffer.cursorRow, 0)
        XCTAssertEqual(buffer.cursorColumn, 0)
    }
    
    // MARK: - Resize Tests
    
    func testResizePreservesContent() {
        buffer.putCharacter("A")
        buffer.moveCursor(row: 0, column: 0)
        
        buffer.resize(rows: 48, columns: 120)
        
        XCTAssertEqual(buffer.rows, 48)
        XCTAssertEqual(buffer.columns, 120)
        XCTAssertEqual(buffer.grid[0][0].character, "A")
    }
    
    func testResizeClampsCursor() {
        buffer.moveCursor(row: 20, column: 70)
        buffer.resize(rows: 10, columns: 40)
        
        XCTAssertEqual(buffer.cursorRow, 9)
        XCTAssertEqual(buffer.cursorColumn, 39)
    }
    
    func testResizeExpandsGrid() {
        let originalRows = buffer.rows
        let originalColumns = buffer.columns
        
        buffer.resize(rows: 48, columns: 120)
        
        XCTAssertEqual(buffer.rows, 48)
        XCTAssertEqual(buffer.columns, 120)
        XCTAssertGreaterThan(buffer.rows, originalRows)
        XCTAssertGreaterThan(buffer.columns, originalColumns)
    }
    
    func testResizeShrinksGrid() {
        buffer.putCharacter("A")
        buffer.moveCursor(row: 10, column: 10)
        buffer.putCharacter("B")
        
        buffer.resize(rows: 5, columns: 40)
        
        XCTAssertEqual(buffer.rows, 5)
        XCTAssertEqual(buffer.columns, 40)
        // Content in preserved area should remain
        XCTAssertEqual(buffer.grid[0][0].character, "A")
    }
    
    // MARK: - Scroll Tests
    
    func testScrollUpWhenAtBottom() {
        // Move to last row
        buffer.moveCursor(row: 23, column: 0)
        buffer.putCharacter("X")
        buffer.newline()  // Should trigger scroll
        
        // First row should be gone, cursor at last row
        XCTAssertEqual(buffer.cursorRow, 23)
    }
    
    func testScrollUpPushesContentUp() {
        // Fill first row with identifiable content
        buffer.moveCursor(row: 0, column: 0)
        buffer.putCharacter("A")
        
        // Move to last row and trigger scroll
        buffer.moveCursor(row: 23, column: 0)
        buffer.newline()
        
        // After scroll, first row content should be gone
        XCTAssertEqual(buffer.grid[0][0].character, " ")
    }
    
    func testMultipleScrolls() {
        // Fill multiple rows
        for row in 0..<24 {
            buffer.moveCursor(row: row, column: 0)
            buffer.putCharacter(Character(UnicodeScalar(65 + row)!))  // A, B, C, ...
        }
        
        // Trigger multiple scrolls
        buffer.moveCursor(row: 23, column: 0)
        for _ in 0..<5 {
            buffer.newline()
        }
        
        // After 5 scrolls, first 5 rows should be gone
        XCTAssertEqual(buffer.cursorRow, 23)
    }
    
    // MARK: - Text Attributes Tests
    
    func testTextAttributesAppliedToCell() {
        buffer.currentForegroundColor = .red
        buffer.currentBackgroundColor = .blue
        buffer.currentBold = true
        buffer.putCharacter("X")
        
        XCTAssertEqual(buffer.grid[0][0].foregroundColor, .red)
        XCTAssertEqual(buffer.grid[0][0].backgroundColor, .blue)
        XCTAssertTrue(buffer.grid[0][0].isBold)
    }
    
    func testItalicAttributeAppliedToCell() {
        buffer.currentItalic = true
        buffer.putCharacter("I")
        
        XCTAssertTrue(buffer.grid[0][0].isItalic)
    }
    
    func testUnderlineAttributeAppliedToCell() {
        buffer.currentUnderlined = true
        buffer.putCharacter("U")
        
        XCTAssertTrue(buffer.grid[0][0].isUnderlined)
    }
    
    func testAttributesPersistAcrossCharacters() {
        buffer.currentForegroundColor = .red
        buffer.currentBold = true
        
        buffer.putCharacter("A")
        buffer.putCharacter("B")
        buffer.putCharacter("C")
        
        XCTAssertEqual(buffer.grid[0][0].foregroundColor, .red)
        XCTAssertEqual(buffer.grid[0][1].foregroundColor, .red)
        XCTAssertEqual(buffer.grid[0][2].foregroundColor, .red)
        XCTAssertTrue(buffer.grid[0][0].isBold)
        XCTAssertTrue(buffer.grid[0][1].isBold)
        XCTAssertTrue(buffer.grid[0][2].isBold)
    }
    
    func testDefaultAttributes() {
        XCTAssertEqual(buffer.currentForegroundColor, .green)
        XCTAssertEqual(buffer.currentBackgroundColor, .black)
        XCTAssertFalse(buffer.currentBold)
        XCTAssertFalse(buffer.currentItalic)
        XCTAssertFalse(buffer.currentUnderlined)
    }
    
    // MARK: - Content String Tests
    
    func testContentString() {
        buffer.putCharacter("H")
        buffer.putCharacter("i")
        
        let content = buffer.contentString()
        XCTAssertTrue(content.contains("Hi"))
    }
    
    func testContentStringWithMultipleRows() {
        buffer.putCharacter("A")
        buffer.moveCursor(row: 1, column: 0)
        buffer.putCharacter("B")
        
        let content = buffer.contentString()
        XCTAssertTrue(content.contains("A"))
        XCTAssertTrue(content.contains("B"))
    }
    
    // MARK: - Edge Cases
    
    func testPutCharacterAtExactGridBoundary() {
        // Test at row 22, column 79 to avoid scroll
        buffer.moveCursor(row: 22, column: 79)
        buffer.putCharacter("Z")
        
        XCTAssertEqual(buffer.grid[22][79].character, "Z")
    }
    
    func testCursorAtLastRowNewlineTriggersScroll() {
        buffer.moveCursor(row: 23, column: 0)
        buffer.putCharacter("X")
        
        // This should trigger a scroll
        buffer.newline()
        
        // Cursor should still be at last row after scroll
        XCTAssertEqual(buffer.cursorRow, 23)
    }
    
    func testScrollRegionDefaults() {
        XCTAssertEqual(buffer.scrollTop, 0)
        XCTAssertEqual(buffer.scrollBottom, 23)  // rows - 1
    }
    
    func testTerminalCellEmptyFactory() {
        let emptyCell = TerminalCell.empty
        XCTAssertEqual(emptyCell.character, " ")
        XCTAssertEqual(emptyCell.foregroundColor, .green)
        XCTAssertEqual(emptyCell.backgroundColor, .black)
        XCTAssertFalse(emptyCell.isBold)
        XCTAssertFalse(emptyCell.isItalic)
        XCTAssertFalse(emptyCell.isUnderlined)
    }
}
