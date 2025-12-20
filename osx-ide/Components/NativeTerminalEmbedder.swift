//
//  NativeTerminalEmbedder.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import SwiftUI
import AppKit
import Foundation

/// Reliable terminal implementation with native zsh shell process
@MainActor
class NativeTerminalEmbedder: NSObject, ObservableObject {
    @Published var currentDirectory: URL?
    @Published var errorMessage: String?
    
    private var terminalView: NSTextView?
    private var shellProcess: Process?
    private var readHandle: FileHandle?
    private var writeHandle: FileHandle?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?
    private var isCleaningUp = false
    
    deinit {
        // Note: Can't access MainActor properties in deinit
        // Cleanup should be done via removeEmbedding() before deallocation
        // This is a safety fallback - remove notification observer
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Embed terminal in the specified parent view
    func embedTerminal(in parentView: NSView, directory: URL? = nil) {
        // Clean up any existing terminal first
        cleanup()
        
        self.currentDirectory = directory ?? FileManager.default.homeDirectoryForCurrentUser
        isCleaningUp = false
        
        setupTerminalView(in: parentView)
        startShellProcess()
        
        // Defer error updates to avoid "publishing changes from within view updates" warning
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = nil
        }
    }
    
    /// Setup terminal view
    private func setupTerminalView(in parentView: NSView) {
        // Remove existing terminal view if present
        parentView.subviews.forEach { $0.removeFromSuperview() }
        terminalView = nil
        
        // Ensure parent view has proper setup
        parentView.wantsLayer = true
        
        // Create scroll view for terminal output
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor.black
        scrollView.drawsBackground = true
        
        // Create text view for terminal content
        let terminalView = NSTextView()
        terminalView.isEditable = true
        terminalView.isSelectable = true
        terminalView.isRichText = false
        terminalView.usesRuler = false
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.backgroundColor = NSColor.black
        terminalView.textColor = NSColor.green
        terminalView.insertionPointColor = NSColor.white
        terminalView.alignment = .left
        terminalView.isVerticallyResizable = true
        terminalView.isHorizontallyResizable = true
        terminalView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        terminalView.textContainer?.widthTracksTextView = true
        terminalView.textContainer?.heightTracksTextView = false
        terminalView.textContainer?.lineFragmentPadding = 0
        terminalView.drawsBackground = true
        // Disable spell checking for terminal
        terminalView.isContinuousSpellCheckingEnabled = false
        terminalView.isAutomaticSpellingCorrectionEnabled = false
        // Ensure cursor is visible
        terminalView.insertionPointColor = NSColor.white

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        terminalView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.green,
            .paragraphStyle: paragraphStyle
        ]
        
        // Setup delegate for input handling
        terminalView.delegate = self
        
        // Configure scroll view
        scrollView.documentView = terminalView
        scrollView.contentView.drawsBackground = false
        
        // Add to parent view with proper constraints
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: parentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
        
        // Store reference
        self.terminalView = terminalView
        
        // Don't show welcome message - let the shell handle its own prompt
        // The shell will output its prompt when ready via standard output
    }
    
    /// Start shell process
    private func startShellProcess() {
        // Determine shell path (prefer zsh, fallback to bash)
        let shellPath: String
        if FileManager.default.fileExists(atPath: "/bin/zsh") {
            shellPath = "/bin/zsh"
        } else if FileManager.default.fileExists(atPath: "/bin/bash") {
            shellPath = "/bin/bash"
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "No suitable shell found (zsh or bash required)"
            }
            return
        }
        
        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-i"] // Interactive shell
        
        if let cwd = currentDirectory {
            process.currentDirectoryURL = cwd
        }
        
        process.standardOutput = outputPipe
        process.standardInput = inputPipe
        process.standardError = outputPipe
        
        // Set up environment for proper terminal behavior
        // Use simpler TERM to reduce escape sequence complexity
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm" // Simpler than xterm-256color
        environment["COLUMNS"] = "\(AppConstants.Terminal.defaultColumns)"
        environment["LINES"] = "\(AppConstants.Terminal.defaultRows)"
        // Disable fancy prompts that generate escape sequences
        environment["PROMPT"] = "$ "
        // Suppress zsh's end-of-line marker (% when output lacks newline).
        environment["PROMPT_EOL_MARK"] = ""
        // For zsh, disable oh-my-zsh or other prompt themes
        environment["ZSH_THEME"] = ""
        environment["DISABLE_AUTO_TITLE"] = "true"
        process.environment = environment
        
        // Store references before starting
        self.shellProcess = process
        self.outputPipe = outputPipe
        self.inputPipe = inputPipe
        self.readHandle = outputPipe.fileHandleForReading
        self.writeHandle = inputPipe.fileHandleForWriting
        
        // Setup notification-based reading (non-blocking)
        setupOutputMonitoring()
        
        // Verify we can access the shell executable
        guard FileManager.default.isExecutableFile(atPath: shellPath) else {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Shell at \(shellPath) is not executable"
            }
            cleanup()
            return
        }
        
        do {
            // Try to launch the process
            // Note: If this fails with "task name port right" error, the app may need
            // to be granted Full Disk Access or the user needs to approve it in System Settings
            try process.run()
            
            // Small delay to ensure process starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                if let isRunning = self.shellProcess?.isRunning, !isRunning {
                    self.errorMessage = "Process failed to start. Please grant Full Disk Access in System Settings > Privacy & Security > Full Disk Access, or restart the app."
                    self.cleanup()
                }
            }
        } catch let error as NSError {
            // Provide detailed error information
            var errorDetails = "Failed to start shell: \(error.localizedDescription)"
            if error.code == 5 || error.localizedDescription.contains("task name port") {
                errorDetails = "Permission denied: Unable to spawn shell process.\n\n" +
                    "Solution: Grant Full Disk Access in System Settings > Privacy & Security > Full Disk Access, then restart the app."
            }
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = errorDetails
            }
            print("Process launch error: \(errorDetails)")
            print("Full error: \(error)")
            cleanup()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Failed to start shell: \(error.localizedDescription)"
            }
            print("Process launch error: \(error)")
            cleanup()
        }
    }
    
    /// Setup notification-based output monitoring (replaces blocking timer)
    private func setupOutputMonitoring() {
        guard let readHandle = readHandle else { return }
        
        // Enable async reading with proper actor isolation
        // Note: readabilityHandler is the preferred non-blocking approach
        readHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF or process ended - check on main actor
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.shellProcess?.isRunning == false {
                        self.handleProcessTerminated()
                    }
                }
                return
            }
            
            // Process data on main thread
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.handleOutputData(data)
            }
        }
    }
    
    @objc private func handleOutputNotification(_ notification: Notification) {
        guard let handle = notification.object as? FileHandle,
              let data = notification.userInfo?[NSFileHandleNotificationDataItem] as? Data else {
            return
        }
        
        handleOutputData(data)
        
        // Continue reading
        if !isCleaningUp {
            handle.readInBackgroundAndNotify()
        }
    }
    
    private func handleOutputData(_ data: Data) {
        guard !isCleaningUp, let output = String(data: data, encoding: .utf8) else { return }
        appendOutput(output)
    }
    
    private func handleProcessTerminated() {
        guard !isCleaningUp else { return }
        appendOutput("\n[Process terminated]\n")
    }
    
    /// Append output to terminal with ANSI escape sequence handling
    private func appendOutput(_ text: String) {
        guard !isCleaningUp, let terminalView = terminalView else { return }
        
        // Parse and render ANSI escape sequences
        let processedText = processANSIEscapeSequences(text)
        
        // Only update if there's actual content (skip cursor positioning sequences)
        guard processedText.length > 0 else { return }
        
        // Update text view on main thread to avoid publishing warnings
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let terminalView = self.terminalView, !self.isCleaningUp else { return }
            
            // Use textStorage for proper attributed string handling
            if let textStorage = terminalView.textStorage {
                // Append to end of text storage
                textStorage.append(processedText)
                
                // Move cursor to end for proper display
                let endRange = NSRange(location: textStorage.length, length: 0)
                terminalView.setSelectedRange(endRange)
            } else {
                // Fallback: set string directly
                terminalView.string += processedText.string
                terminalView.textColor = NSColor.green
                let range = NSRange(location: terminalView.string.count, length: 0)
                terminalView.setSelectedRange(range)
            }
            
            // Scroll to bottom and ensure visibility
            let range = NSRange(location: terminalView.string.count, length: 0)
            terminalView.scrollRangeToVisible(range)
            terminalView.needsDisplay = true
            
            // Ensure the scroll view is visible
            if let scrollView = terminalView.enclosingScrollView {
                scrollView.needsDisplay = true
            }
        }
    }
    
    /// Process ANSI escape sequences and return attributed string
    private func processANSIEscapeSequences(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        var currentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.green,
            .paragraphStyle: paragraphStyle
        ]
        
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\u{1B}" { // ESC character
                // Parse escape sequence
                if let (newIndex, newAttributes, shouldSkip) = parseANSISequence(text, from: i) {
                    if !shouldSkip {
                        currentAttributes.merge(newAttributes) { (_, new) in new }
                    }
                    i = newIndex
                    continue
                }
            }
            
            // Handle control characters
            if text[i] == "\r" {
                // Carriage return - move to start of line (handled by text view)
                i = text.index(after: i)
                continue
            } else if text[i] == "\u{08}" || text[i] == "\u{7F}" {
                // Backspace - handled by text view
                i = text.index(after: i)
                continue
            }
            
            // Regular character
            let char = String(text[i])
            
            // Filter out problematic characters that cause white lines
            // Skip zsh's partial line indicator (%) when it appears alone
            if char == "%" && (i == text.startIndex || text[text.index(before: i)] == "\n") {
                // Check if next char is whitespace or control - if so, skip the %
                let nextIndex = text.index(after: i)
                if nextIndex < text.endIndex {
                    let nextChar = text[nextIndex]
                    if nextChar.isWhitespace || nextChar == "\u{1B}" || nextChar == "\r" {
                        i = nextIndex
                        continue
                    }
                }
            }
            
            // Skip other control characters except newline and tab
            let scalarValue = char.unicodeScalars.first?.value ?? 0
            if scalarValue < 32 && char != "\n" && char != "\t" {
                i = text.index(after: i)
                continue
            }
            
            result.append(NSAttributedString(string: char, attributes: currentAttributes))
            i = text.index(after: i)
        }
        
        return result
    }
    
    /// Parse ANSI escape sequence starting at the given index
    /// Returns: (newIndex, attributes, shouldSkipOutput)
    private func parseANSISequence(_ text: String, from start: String.Index) -> (newIndex: String.Index, attributes: [NSAttributedString.Key: Any], shouldSkip: Bool)? {
        guard start < text.endIndex, text[start] == "\u{1B}" else { return nil }
        
        var i = text.index(after: start)
        guard i < text.endIndex else { return (i, [:], false) }
        
        if text[i] == "[" {
            // CSI sequence
            i = text.index(after: i)
            return parseCSISequence(text, from: i, baseAttributes: [:])
        } else if text[i] == "]" {
            // OSC sequence (Operating System Command) - skip entirely
            // Skip until BEL or ESC \
            while i < text.endIndex {
                if text[i] == "\u{07}" || (text[i] == "\u{1B}" && i < text.index(before: text.endIndex) && text[text.index(after: i)] == "\\") {
                    if text[i] == "\u{1B}" {
                        i = text.index(after: i) // Skip ESC
                    }
                    i = text.index(after: i) // Skip \ or BEL
                    break
                }
                i = text.index(after: i)
            }
            return (i, [:], true) // OSC sequences don't produce output
        } else if text[i] == "c" {
            // RIS (Reset to Initial State) - skip
            i = text.index(after: i)
            return (i, [:], true)
        }
        
        // Unknown escape sequence, skip ESC character
        return (i, [:], false)
    }
    
    /// Parse CSI (Control Sequence Introducer) sequence
    /// Returns: (newIndex, attributes, shouldSkipOutput)
    private func parseCSISequence(_ text: String, from start: String.Index, baseAttributes: [NSAttributedString.Key: Any]) -> (newIndex: String.Index, attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        var i = start
        var parameters: [Int] = []
        var currentParam = ""
        var attributes = baseAttributes
        
        // Parse parameters
        while i < text.endIndex {
            let char = text[i]
            
            if char.isNumber {
                currentParam.append(char)
            } else if char == ";" {
                if !currentParam.isEmpty {
                    parameters.append(Int(currentParam) ?? 0)
                    currentParam = ""
                }
            } else if char >= "A" && char <= "Z" || char >= "a" && char <= "z" {
                if !currentParam.isEmpty {
                    parameters.append(Int(currentParam) ?? 0)
                }
                
                // Handle different CSI commands
                switch char {
                case "m": // SGR (Select Graphic Rendition)
                    attributes = applySGRParameters(parameters, to: attributes)
                    i = text.index(after: i)
                    return (i, attributes, false)
                case "K": // EL (Erase in Line) - clear from cursor to end of line
                    // Don't output anything, just skip
                    i = text.index(after: i)
                    return (i, attributes, true)
                case "J": // ED (Erase in Display) - clear screen
                    // Don't output anything, just skip
                    i = text.index(after: i)
                    return (i, attributes, true)
                case "H", "f": // CUP (Cursor Position) - cursor positioning
                    // Don't output anything, just skip
                    i = text.index(after: i)
                    return (i, attributes, true)
                case "A", "B", "C", "D": // Cursor movement (up, down, forward, back)
                    // Don't output anything, just skip
                    i = text.index(after: i)
                    return (i, attributes, true)
                case "s": // Save cursor position
                    i = text.index(after: i)
                    return (i, attributes, true)
                case "u": // Restore cursor position
                    i = text.index(after: i)
                    return (i, attributes, true)
                default:
                    // Unknown command, skip
                    i = text.index(after: i)
                    return (i, attributes, true)
                }
            }
            
            i = text.index(after: i)
        }
        
        return (i, attributes, false)
    }
    
    /// Apply SGR (Select Graphic Rendition) parameters to attributes
    private func applySGRParameters(_ parameters: [Int], to baseAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        
        for param in parameters.isEmpty ? [0] : parameters {
            switch param {
            case 0: // Reset
                attributes = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.green,
                    .paragraphStyle: paragraphStyle
                ]
            case 1: // Bold
                if let font = attributes[.font] as? NSFont {
                    // Create bold version of the font
                    let boldFont = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
                    attributes[.font] = boldFont
                }
            case 7: // Reverse video (invert) - used for selection/highlighting
                // For reverse video, use subtle highlighting instead of full inversion
                // This prevents white blocks from appearing
                let fg = attributes[.foregroundColor] as? NSColor ?? NSColor.green
                attributes[.foregroundColor] = NSColor.white
                attributes[.backgroundColor] = fg.withAlphaComponent(0.2) // Subtle background
            case 27: // Disable reverse video (SGR code 27 = 7 + 20)
                // Reset to normal
                attributes[.foregroundColor] = NSColor.green
                attributes[.backgroundColor] = NSColor.clear
            case 30...37: // Foreground colors
                attributes[.foregroundColor] = ansiColor(param - 30)
            case 40...47: // Background colors
                attributes[.backgroundColor] = ansiColor(param - 40)
            default:
                break
            }
        }
        
        return attributes
    }
    
    /// Get NSColor for ANSI color code (0-7)
    private func ansiColor(_ code: Int) -> NSColor {
        switch code {
        case 0: return .black
        case 1: return .red
        case 2: return .green
        case 3: return .yellow
        case 4: return .blue
        case 5: return .magenta
        case 6: return .cyan
        case 7: return .white
        default: return .green
        }
    }
    
    /// Send command to shell (legacy method, kept for compatibility)
    private func sendCommand(_ command: String) {
        guard !isCleaningUp, let writeHandle = writeHandle else { return }
        guard let data = (command + "\n").data(using: .utf8) else { return }
        
        // Write on background queue to avoid blocking
        DispatchQueue.global(qos: .userInitiated).async {
            writeHandle.write(data)
        }
    }
    
    /// Execute command (legacy method, kept for compatibility)
    func executeCommand(_ command: String) {
        guard !isCleaningUp else { return }
        sendCommand(command)
    }
    
    /// Change directory
    func changeDirectory(to url: URL) {
        guard !isCleaningUp else { return }
        DispatchQueue.main.async { [weak self] in
            self?.currentDirectory = url
        }
        executeCommand("cd '\(url.path)'")
    }
    
    /// Clear terminal
    func clearTerminal() {
        guard !isCleaningUp else { return }
        terminalView?.string = ""
    }
    
    /// Remove terminal and cleanup resources
    func removeEmbedding() {
        cleanup()
    }
    
    /// Cleanup all resources
    private func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self)
        
        // Stop reading
        readHandle?.readabilityHandler = nil
        
        // Terminate process without blocking the main actor
        if let process = shellProcess, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + AppConstants.Time.processTerminationTimeout) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
        
        // Close file handles
        readHandle?.closeFile()
        writeHandle?.closeFile()
        
        // Remove view
        terminalView?.removeFromSuperview()
        
        // Clear references
        shellProcess = nil
        readHandle = nil
        writeHandle = nil
        outputPipe = nil
        inputPipe = nil
        terminalView = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = nil
        }
    }
    
    /// Check if terminal is available
    static func isTerminalAvailable() -> Bool {
        return FileManager.default.fileExists(atPath: "/bin/zsh") || 
               FileManager.default.fileExists(atPath: "/bin/bash")
    }
}

// MARK: - NSTextViewDelegate
extension NativeTerminalEmbedder: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !isCleaningUp, let writeHandle = writeHandle else { return false }
        
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Send newline to shell
            sendInput("\n".data(using: .utf8) ?? Data())
            // Allow text view to add newline for display
            return false
        } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            // Send backspace (DEL) to shell
            sendInput("\u{7F}".data(using: .utf8) ?? Data())
            // Allow text view to handle backspace for display
            return false
        } else if commandSelector == #selector(NSResponder.deleteForward(_:)) {
            // Send delete forward sequence
            sendInput("\u{1B}[3~".data(using: .utf8) ?? Data())
            return false
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Ctrl+C - interrupt running command (like top, vim, etc.)
            if let process = shellProcess, process.isRunning {
                process.interrupt()
            }
            // Also send Ctrl+C character (\x03) to shell for proper handling
            sendInput("\u{03}".data(using: .utf8) ?? Data())
            // Don't prevent text view from showing ^C if it wants to
            return false
        }
        
        return false
    }
    
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard !isCleaningUp else { return false }
        
        // Send input to shell and rely on shell echo to display characters.
        if let replacementString = replacementString {
            // Send to shell
            if let data = replacementString.data(using: .utf8) {
                sendInput(data)
            }

            // Allow local echo for immediate feedback.
            return true
        }
        
        return false
    }
    
    /// Send input data directly to shell process
    private func sendInput(_ data: Data) {
        guard !isCleaningUp, let writeHandle = writeHandle else { return }
        
        // Write on background queue to avoid blocking
        DispatchQueue.global(qos: .userInitiated).async {
            writeHandle.write(data)
        }
    }
}
