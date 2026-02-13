import AppKit

/// Represents a single cell in the terminal screen
struct TerminalCell {
    var character: Character
    var foregroundColor: NSColor
    var backgroundColor: NSColor
    var isBold: Bool
    var isItalic: Bool
    var isUnderlined: Bool
    
    static let empty = TerminalCell(
        character: " ",
        foregroundColor: .green,
        backgroundColor: .black,
        isBold: false,
        isItalic: false,
        isUnderlined: false
    )
}

/// Virtual terminal screen buffer that models the terminal as a 2D grid
@MainActor
class TerminalScreenBuffer {
    private(set) var rows: Int
    private(set) var columns: Int
    private(set) var grid: [[TerminalCell]]
    
    // Cursor position
    var cursorRow: Int = 0
    var cursorColumn: Int = 0
    
    // Scroll region (for DECSTBM support)
    var scrollTop: Int = 0
    var scrollBottom: Int { rows - 1 }
    
    // Current text attributes
    var currentForegroundColor: NSColor = .green
    var currentBackgroundColor: NSColor = .black
    var currentBold: Bool = false
    var currentItalic: Bool = false
    var currentUnderlined: Bool = false
    
    init(rows: Int = 24, columns: Int = 80) {
        self.rows = rows
        self.columns = columns
        self.grid = Array(repeating: Array(repeating: .empty, count: columns), count: rows)
    }
    
    /// Resize the screen buffer
    func resize(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
        
        // Create new grid, preserving existing content where possible
        var newGrid = Array(repeating: Array(repeating: TerminalCell.empty, count: columns), count: rows)
        for row in 0..<min(rows, grid.count) {
            for col in 0..<min(columns, grid[row].count) {
                newGrid[row][col] = grid[row][col]
            }
        }
        grid = newGrid
        
        // Clamp cursor position
        cursorRow = min(cursorRow, rows - 1)
        cursorColumn = min(cursorColumn, columns - 1)
    }
    
    /// Put a character at the current cursor position
    func putCharacter(_ char: Character) {
        guard cursorRow < rows && cursorColumn < columns else { return }
        
        grid[cursorRow][cursorColumn] = TerminalCell(
            character: char,
            foregroundColor: currentForegroundColor,
            backgroundColor: currentBackgroundColor,
            isBold: currentBold,
            isItalic: currentItalic,
            isUnderlined: currentUnderlined
        )
        
        cursorColumn += 1
        if cursorColumn >= columns {
            cursorColumn = 0
            advanceRow()
        }
    }
    
    /// Move cursor to specified position
    func moveCursor(row: Int, column: Int) {
        cursorRow = max(0, min(row, rows - 1))
        cursorColumn = max(0, min(column, columns - 1))
    }
    
    /// Move cursor relative to current position
    func moveCursorRelative(rowDelta: Int, columnDelta: Int) {
        cursorRow = max(0, min(cursorRow + rowDelta, rows - 1))
        cursorColumn = max(0, min(cursorColumn + columnDelta, columns - 1))
    }
    
    /// Carriage return - move cursor to beginning of line
    func carriageReturn() {
        cursorColumn = 0
    }
    
    /// Newline - move cursor down, scroll if needed
    func newline() {
        advanceRow()
    }
    
    /// Backspace - move cursor back one position
    func backspace() {
        if cursorColumn > 0 {
            cursorColumn -= 1
        }
    }
    
    /// Tab - move to next tab stop (every 8 columns)
    func tab() {
        let nextTab = ((cursorColumn / 8) + 1) * 8
        cursorColumn = min(nextTab, columns - 1)
    }
    
    /// Erase from cursor to end of line
    func eraseToEndOfLine() {
        for col in cursorColumn..<columns {
            grid[cursorRow][col] = .empty
        }
    }
    
    /// Erase from beginning of line to cursor
    func eraseToStartOfLine() {
        for col in 0...cursorColumn {
            grid[cursorRow][col] = .empty
        }
    }
    
    /// Erase entire line
    func eraseLine() {
        for col in 0..<columns {
            grid[cursorRow][col] = .empty
        }
    }
    
    /// Erase from cursor to end of screen
    func eraseToEndOfScreen() {
        // Erase rest of current line
        eraseToEndOfLine()
        // Erase all following lines
        for row in (cursorRow + 1)..<rows {
            for col in 0..<columns {
                grid[row][col] = .empty
            }
        }
    }
    
    /// Erase from beginning of screen to cursor
    func eraseToStartOfScreen() {
        // Erase all preceding lines
        for row in 0..<cursorRow {
            for col in 0..<columns {
                grid[row][col] = .empty
            }
        }
        // Erase start of current line to cursor
        eraseToStartOfLine()
    }
    
    /// Erase entire screen
    func eraseScreen() {
        for row in 0..<rows {
            for col in 0..<columns {
                grid[row][col] = .empty
            }
        }
    }
    
    /// Erase a specific number of characters starting at cursor position
    func eraseCharacters(_ count: Int) {
        for i in 0..<count {
            let col = cursorColumn + i
            if col < columns {
                grid[cursorRow][col] = .empty
            }
        }
    }
    
    /// Clear screen and reset cursor
    func clear() {
        eraseScreen()
        cursorRow = 0
        cursorColumn = 0
    }
    
    /// Get the content as a string (for debugging)
    func contentString() -> String {
        grid.map { row in
            String(row.map { $0.character })
        }.joined(separator: "\n")
    }
    
    // MARK: - Private Methods
    
    private func advanceRow() {
        cursorRow += 1
        if cursorRow >= rows {
            scrollUp()
            cursorRow = rows - 1
        }
    }
    
    private func scrollUp() {
        // Remove top line, add empty line at bottom
        grid.removeFirst()
        grid.append(Array(repeating: .empty, count: columns))
    }
}
