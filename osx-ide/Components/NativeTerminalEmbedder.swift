//
//  NativeTerminalEmbedder.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import SwiftUI
import AppKit
import Foundation

@MainActor
protocol ShellManaging: AnyObject {
    var delegate: ShellManagerDelegate? { get set }
    func start(in directory: URL?)
    func sendInput(_ text: String)
    func interrupt()
    func terminate()
}

extension ShellManager: ShellManaging {}

/// Reliable terminal UI implementation that integrates with ShellManager
@MainActor
class NativeTerminalEmbedder: NSObject, ObservableObject {
    @Published var currentDirectory: URL?
    @Published var errorMessage: String?
    
    var terminalView: NSTextView?
    private let shellManager: ShellManaging
    private var isCleaningUp = false
    
    var fontSize: CGFloat = 12
    var fontFamily: String = "SF Mono"
    
    var currentLineStartLocation: Int = 0
    var cursorColumn: Int = 0
    var currentTextAttributes: [NSAttributedString.Key: Any] = [:]
    var pendingEraseToEndOfLine: Bool = false

    private let eventBus: EventBusProtocol

    init(shellManager: ShellManaging = ShellManager(), eventBus: EventBusProtocol) {
        self.shellManager = shellManager
        self.eventBus = eventBus
        super.init()
        shellManager.delegate = self
    }

    final class TerminalTextView: NSTextView {
        weak var inputDelegate: NativeTerminalEmbedder?

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func keyDown(with event: NSEvent) {
            if let s = event.characters {
                inputDelegate?.shellManager.sendInput(s)
            }
        }

        override func doCommand(by selector: Selector) {
            guard let inputDelegate else {
                super.doCommand(by: selector)
                return
            }

            if selector == #selector(NSResponder.insertNewline(_:)) {
                inputDelegate.shellManager.sendInput("\n")
                return
            }
            if selector == #selector(NSResponder.deleteBackward(_:)) {
                inputDelegate.shellManager.sendInput("\u{7F}")
                return
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                inputDelegate.shellManager.interrupt()
                return
            }

            super.doCommand(by: selector)
        }
    }
    
    
    deinit {
        // Observer cleanup is handled in removeEmbedding
    }
    
    /// Embed terminal in the specified parent view
    func embedTerminal(in parentView: NSView, directory: URL? = nil, fontSize: Double? = nil, fontFamily: String? = nil) {
        if let fontSize = fontSize {
            self.fontSize = CGFloat(fontSize)
        }
        if let fontFamily = fontFamily {
            self.fontFamily = fontFamily
        }
        
        let newDir = directory?.standardizedFileURL
        
        // If we already have a terminal view and process, check if we just need to change dir
        if let existingView = terminalView {
            if existingView.enclosingScrollView?.superview == parentView || existingView.superview == parentView {
                if let current = self.currentDirectory?.standardizedFileURL, let new = newDir, current.path != new.path {
                    DispatchQueue.main.async { [weak self] in
                        self?.currentDirectory = new
                    }
                    shellManager.sendInput("cd '\(new.path)'\n")
                }
                return
            }
        }
        
        cleanup()
        
        let targetDir = newDir ?? FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        
        DispatchQueue.main.async { [weak self] in
            self?.currentDirectory = targetDir
            self?.errorMessage = nil
        }
        
        isCleaningUp = false
        setupTerminalView(in: parentView)
        shellManager.start(in: targetDir)
    }

    func focusTerminal() {
        guard let terminalView else { return }

        terminalView.window?.makeFirstResponder(terminalView)

        let endLocation = terminalView.string.utf16.count
        let endRange = NSRange(location: endLocation, length: 0)
        terminalView.setSelectedRange(endRange)
        terminalView.scrollRangeToVisible(endRange)
    }
    
    /// Setup terminal view
    private func setupTerminalView(in parentView: NSView) {
        parentView.subviews.forEach { $0.removeFromSuperview() }
        terminalView = nil
        parentView.wantsLayer = true
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor.black
        scrollView.drawsBackground = true
        
        let terminalView = TerminalTextView()
        terminalView.inputDelegate = self
        terminalView.isEditable = true
        terminalView.isSelectable = true
        terminalView.isRichText = false
        terminalView.usesRuler = false
        terminalView.font = resolveFont(size: fontSize, family: fontFamily)
        terminalView.backgroundColor = NSColor.black
        terminalView.textColor = NSColor.green
        terminalView.insertionPointColor = NSColor.white
        terminalView.alignment = .left
        terminalView.isVerticallyResizable = true
        terminalView.isHorizontallyResizable = true
        terminalView.textContainer?.lineFragmentPadding = 5
        terminalView.drawsBackground = true
        terminalView.isContinuousSpellCheckingEnabled = false
        terminalView.delegate = self
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        terminalView.typingAttributes = [
            .font: resolveFont(size: fontSize, family: fontFamily),
            .foregroundColor: NSColor.green,
            .paragraphStyle: paragraphStyle
        ]
        
        scrollView.documentView = terminalView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: parentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
        
        self.terminalView = terminalView

        currentLineStartLocation = 0
        cursorColumn = 0
        currentTextAttributes = terminalView.typingAttributes
        pendingEraseToEndOfLine = false
    }
    
    /// Update terminal font
    func updateFont(size: Double, family: String) {
        self.fontSize = CGFloat(size)
        self.fontFamily = family
        
        guard let terminalView = terminalView else { return }
        
        let newFont = resolveFont(size: self.fontSize, family: self.fontFamily)
        terminalView.font = newFont
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        terminalView.typingAttributes = [
            .font: newFont,
            .foregroundColor: NSColor.green,
            .paragraphStyle: paragraphStyle
        ]
        
        // Refresh existing content font if needed
        if let storage = terminalView.textStorage {
            storage.beginEditing()
            storage.addAttribute(.font, value: newFont, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
    }
    
    func resolveFont(size: CGFloat, family: String, weight: NSFont.Weight = .regular) -> NSFont {
        if let font = NSFont(name: family, size: size) {
            return NSFontManager.shared.convert(font, toHaveTrait: weight == .bold ? .boldFontMask : .unboldFontMask)
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
    
    private func appendOutput(_ text: String) {
        guard !isCleaningUp, terminalView != nil else { return }

        eventBus.publish(TerminalOutputProducedEvent(output: text))

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let terminalView = self.terminalView, !self.isCleaningUp else { return }
            let shouldAutoscroll = self.isNearBottom(terminalView)
            self.applyTerminalOutput(text, to: terminalView)

            if shouldAutoscroll {
                let range = NSRange(location: terminalView.string.count, length: 0)
                terminalView.setSelectedRange(range)
                terminalView.scrollRangeToVisible(range)
            }
        }
    }

    private func isNearBottom(_ terminalView: NSTextView) -> Bool {
        guard let scrollView = terminalView.enclosingScrollView else { return true }
        let contentHeight = scrollView.contentView.bounds.height
        let maxY = scrollView.contentView.bounds.maxY
        let docHeight = scrollView.documentView?.bounds.height ?? 0
        if contentHeight <= 0 { return true }
        return (docHeight - maxY) < max(40, contentHeight * 0.15)
    }

    private func applyTerminalOutput(_ text: String, to terminalView: NSTextView) {
        guard let textStorage = terminalView.textStorage else {
            // Fallback to old behavior if textStorage isn't available.
            terminalView.string += processANSIEscapeSequences(text).string
            currentLineStartLocation = terminalView.string.count
            cursorColumn = 0
            currentTextAttributes = terminalView.typingAttributes
            pendingEraseToEndOfLine = false
            return
        }

        if currentTextAttributes.isEmpty {
            currentTextAttributes = terminalView.typingAttributes
        }

        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]

            if ch == "\u{1B}" {
                if let parsed = parseANSISequence(text, from: i) {
                    i = parsed.newIndex
                    if !parsed.shouldSkip {
                        currentTextAttributes.merge(parsed.attributes) { _, new in new }
                    }
                    continue
                }
            }

            if ch == "\n" {
                appendNewline(into: textStorage)
                i = text.index(after: i)
                continue
            }

            if ch == "\r" {
                i = handleCarriageReturn(in: text, at: i)
                continue
            }

            if ch == "\u{08}" || ch == "\u{7F}" {
                handleBackspace()
                i = text.index(after: i)
                continue
            }

            if shouldSkipControlCharacter(ch) {
                i = text.index(after: i)
                continue
            }

            if ch == "\t" {
                appendTab(into: textStorage)
                i = text.index(after: i)
                continue
            }

            if pendingEraseToEndOfLine {
                eraseToEndOfLine(in: textStorage)
                pendingEraseToEndOfLine = false
            }

            putCharacter(String(ch), into: textStorage)
            i = text.index(after: i)
        }
    }

    private func appendNewline(into textStorage: NSTextStorage) {
        textStorage.append(NSAttributedString(string: "\n", attributes: currentTextAttributes))
        currentLineStartLocation = textStorage.length
        cursorColumn = 0
        pendingEraseToEndOfLine = false
    }

    private func handleCarriageReturn(in text: String, at index: String.Index) -> String.Index {
        // Treat CRLF as newline to avoid arming redraw erasure on Enter.
        let nextIndex = text.index(after: index)
        if nextIndex < text.endIndex, text[nextIndex] == "\n" {
            return nextIndex
        }

        cursorColumn = 0
        // Shells redraw the current line by carriage returning and rewriting.
        // Clear stale tail once before the next printable character to avoid leftover prompt chars.
        pendingEraseToEndOfLine = true
        return nextIndex
    }

    private func handleBackspace() {
        cursorColumn = max(0, cursorColumn - 1)
        pendingEraseToEndOfLine = false
    }

    private func shouldSkipControlCharacter(_ ch: Character) -> Bool {
        // Filter other control chars except tab.
        let scalarValue = ch.unicodeScalars.first?.value ?? 0
        return scalarValue < 32 && ch != "\t"
    }

    private func appendTab(into textStorage: NSTextStorage) {
        // Treat tab as spaces (simple rendering).
        for _ in 0..<4 {
            putCharacter(" ", into: textStorage)
        }
        pendingEraseToEndOfLine = false
    }

    func eraseToEndOfLine(in textStorage: NSTextStorage) {
        let full = textStorage.string as NSString
        let startIndex = max(0, currentLineStartLocation + cursorColumn)
        let searchRange = NSRange(location: currentLineStartLocation, length: max(0, full.length - currentLineStartLocation))
        let newlineRange = full.range(of: "\n", options: [], range: searchRange)
        let lineEnd = (newlineRange.location == NSNotFound) ? full.length : newlineRange.location
        if startIndex < lineEnd {
            textStorage.deleteCharacters(in: NSRange(location: startIndex, length: lineEnd - startIndex))
        }
    }

    func eraseInLine(mode: Int, in textStorage: NSTextStorage) {
        let full = textStorage.string as NSString
        let lineRange = NSRange(location: currentLineStartLocation, length: max(0, full.length - currentLineStartLocation))
        let newlineRange = full.range(of: "\n", options: [], range: lineRange)
        let lineEnd = (newlineRange.location == NSNotFound) ? full.length : newlineRange.location
        let cursorIndex = max(0, min(currentLineStartLocation + cursorColumn, lineEnd))

        switch mode {
        case 0:
            eraseToEndOfLine(in: textStorage)
        case 1:
            // From start of line to cursor (inclusive in terminals, but inclusive isn't critical for us).
            if currentLineStartLocation < cursorIndex {
                textStorage.deleteCharacters(in: NSRange(location: currentLineStartLocation, length: cursorIndex - currentLineStartLocation))
                currentLineStartLocation = max(0, currentLineStartLocation)
                cursorColumn = 0
            }
        case 2:
            // Entire line.
            if currentLineStartLocation < lineEnd {
                textStorage.deleteCharacters(in: NSRange(location: currentLineStartLocation, length: lineEnd - currentLineStartLocation))
            }
            cursorColumn = 0
        default:
            break
        }
    }

    func deleteCharacters(_ count: Int, in textStorage: NSTextStorage) {
        guard count > 0 else { return }
        let full = textStorage.string as NSString
        let lineRange = NSRange(location: currentLineStartLocation, length: max(0, full.length - currentLineStartLocation))
        let newlineRange = full.range(of: "\n", options: [], range: lineRange)
        let lineEnd = (newlineRange.location == NSNotFound) ? full.length : newlineRange.location
        let cursorIndex = max(0, min(currentLineStartLocation + cursorColumn, lineEnd))
        let deleteEnd = min(lineEnd, cursorIndex + count)
        if cursorIndex < deleteEnd {
            textStorage.deleteCharacters(in: NSRange(location: cursorIndex, length: deleteEnd - cursorIndex))
        }
    }

    func putCharacter(_ character: String, into textStorage: NSTextStorage) {
        let absoluteCursor = max(0, currentLineStartLocation + cursorColumn)

        // Find end-of-line (or end-of-buffer) so we overwrite within the line.
        let full = textStorage.string as NSString
        let searchRange = NSRange(location: currentLineStartLocation, length: max(0, full.length - currentLineStartLocation))
        let newlineRange = full.range(of: "\n", options: [], range: searchRange)
        let lineEnd = (newlineRange.location == NSNotFound) ? full.length : newlineRange.location

        if absoluteCursor < lineEnd {
            // Overwrite within existing line.
            textStorage.replaceCharacters(in: NSRange(location: absoluteCursor, length: 1), with: NSAttributedString(string: character, attributes: currentTextAttributes))
        } else {
            // Append at end of line (before newline if present).
            let insertLocation = lineEnd
            textStorage.insert(NSAttributedString(string: character, attributes: currentTextAttributes), at: insertLocation)
        }

        cursorColumn += 1
    }

    func clearTerminal() {
        guard !isCleaningUp else { return }
        terminalView?.string = ""
    }

    func removeEmbedding() {
        cleanup()
    }
    
    private func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        
        shellManager.terminate()
        terminalView?.removeFromSuperview()
        terminalView = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = nil
        }
    }
}

// MARK: - ShellManagerDelegate
extension NativeTerminalEmbedder: ShellManagerDelegate {
    func shellManager(_ manager: ShellManager, didProduceOutput output: String) {
        appendOutput(output)
    }
    
    func shellManager(_ manager: ShellManager, didFailWithError error: String) {
        self.errorMessage = error
    }
    
    func shellManagerDidTerminate(_ manager: ShellManager) {
        appendOutput("\n[Process terminated]\n")
    }
}

// MARK: - NSTextViewDelegate
extension NativeTerminalEmbedder: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool { false }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool { false }
}
