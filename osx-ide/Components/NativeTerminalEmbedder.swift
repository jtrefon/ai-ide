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
            if let characters = event.characters {
                inputDelegate?.shellManager.sendInput(characters)
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
    func embedTerminal(
        in parentView: NSView,
        directory: URL? = nil,
        fontSize: Double? = nil,
        fontFamily: String? = nil
    ) {
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
                if let current = self.currentDirectory?.standardizedFileURL,
                   let new = newDir,
                   current.path != new.path {
                    Task { @MainActor [weak self] in
                        self?.currentDirectory = new
                    }
                    shellManager.sendInput("cd '\(new.path)'\n")
                }
                return
            }
        }

        cleanup()

        let targetDir = newDir ?? FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL

        Task { @MainActor [weak self] in
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
        terminalView.setAccessibilityIdentifier("TerminalTextView")

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

        Task { @MainActor [weak self] in
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
}

extension NativeTerminalEmbedder {
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

        applyTerminalOutputCharacters(text, into: textStorage)
    }

    private func applyTerminalOutputCharacters(_ text: String, into textStorage: NSTextStorage) {
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]

            if let newIndex = consumeEscapeSequenceIfPresent(text, at: index) {
                index = newIndex
                continue
            }

            if let newIndex = consumeLineBreakIfPresent(text, at: index, into: textStorage) {
                index = newIndex
                continue
            }

            if let newIndex = consumeEditingControlIfPresent(text, at: index, into: textStorage) {
                index = newIndex
                continue
            }

            if consumeIgnoredControlIfPresent(ch) {
                index = text.index(after: index)
                continue
            }

            if pendingEraseToEndOfLine {
                eraseToEndOfLine(in: textStorage)
                pendingEraseToEndOfLine = false
            }

            putCharacter(String(ch), into: textStorage)
            index = text.index(after: index)
        }
    }

    private func consumeEscapeSequenceIfPresent(_ text: String, at index: String.Index) -> String.Index? {
        guard text[index] == "\u{1B}" else { return nil }
        guard let parsed = parseANSISequence(text, from: index) else { return nil }
        if !parsed.shouldSkip {
            currentTextAttributes.merge(parsed.attributes) { _, new in new }
        }
        return parsed.newIndex
    }

    private func consumeLineBreakIfPresent(
        _ text: String,
        at index: String.Index,
        into textStorage: NSTextStorage
    ) -> String.Index? {
        let ch = text[index]
        if ch == "\n" {
            appendNewline(into: textStorage)
            return text.index(after: index)
        }

        if ch == "\r" {
            return handleCarriageReturn(in: text, at: index)
        }

        return nil
    }

    private func consumeEditingControlIfPresent(
        _ text: String,
        at index: String.Index,
        into textStorage: NSTextStorage
    ) -> String.Index? {
        let ch = text[index]
        if ch == "\u{08}" || ch == "\u{7F}" {
            handleBackspace()
            return text.index(after: index)
        }

        if ch == "\t" {
            appendTab(into: textStorage)
            return text.index(after: index)
        }

        return nil
    }

    private func consumeIgnoredControlIfPresent(_ ch: Character) -> Bool {
        shouldSkipControlCharacter(ch)
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

    private func currentLineBounds(in textStorage: NSTextStorage) -> (full: NSString, lineEnd: Int) {
        let full = textStorage.string as NSString
        let lineRange = NSRange(
            location: currentLineStartLocation,
            length: max(0, full.length - currentLineStartLocation)
        )
        let newlineRange = full.range(of: "\n", options: [], range: lineRange)
        let lineEnd = (newlineRange.location == NSNotFound) ? full.length : newlineRange.location
        return (full: full, lineEnd: lineEnd)
    }

    func eraseToEndOfLine(in textStorage: NSTextStorage) {
        let bounds = currentLineBounds(in: textStorage)
        let startIndex = max(0, currentLineStartLocation + cursorColumn)
        if startIndex < bounds.lineEnd {
            textStorage.deleteCharacters(
                in: NSRange(location: startIndex, length: bounds.lineEnd - startIndex)
            )
        }
    }

    func eraseInLine(mode: Int, in textStorage: NSTextStorage) {
        let bounds = currentLineBounds(in: textStorage)
        let cursorIndex = max(0, min(currentLineStartLocation + cursorColumn, bounds.lineEnd))

        switch mode {
        case 0:
            eraseToEndOfLine(in: textStorage)
        case 1:
            // From start of line to cursor (inclusive in terminals, but inclusive isn't critical for us).
            if currentLineStartLocation < cursorIndex {
                textStorage.deleteCharacters(
                    in: NSRange(
                        location: currentLineStartLocation,
                        length: cursorIndex - currentLineStartLocation
                    )
                )
                currentLineStartLocation = max(0, currentLineStartLocation)
                cursorColumn = 0
            }
        case 2:
            // Entire line.
            if currentLineStartLocation < bounds.lineEnd {
                textStorage.deleteCharacters(
                    in: NSRange(
                        location: currentLineStartLocation,
                        length: bounds.lineEnd - currentLineStartLocation
                    )
                )
            }
            cursorColumn = 0
        default:
            break
        }
    }

    func deleteCharacters(_ count: Int, in textStorage: NSTextStorage) {
        guard count > 0 else { return }
        let bounds = currentLineBounds(in: textStorage)
        let cursorIndex = max(0, min(currentLineStartLocation + cursorColumn, bounds.lineEnd))
        let deleteEnd = min(bounds.lineEnd, cursorIndex + count)
        if cursorIndex < deleteEnd {
            textStorage.deleteCharacters(in: NSRange(location: cursorIndex, length: deleteEnd - cursorIndex))
        }
    }

    func putCharacter(_ character: String, into textStorage: NSTextStorage) {
        let absoluteCursor = max(0, currentLineStartLocation + cursorColumn)

        // Find end-of-line (or end-of-buffer) so we overwrite within the line.
        let bounds = currentLineBounds(in: textStorage)

        if absoluteCursor < bounds.lineEnd {
            // Overwrite within existing line.
            textStorage.replaceCharacters(
                in: NSRange(location: absoluteCursor, length: 1),
                with: NSAttributedString(
                    string: character,
                    attributes: currentTextAttributes
                )
            )
        } else {
            // Append at end of line (before newline if present).
            let insertLocation = bounds.lineEnd
            textStorage.insert(
                NSAttributedString(string: character, attributes: currentTextAttributes),
                at: insertLocation
            )
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

        Task { @MainActor [weak self] in
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
    func textView(_ textView: NSTextView, doCommandBy _: Selector) -> Bool { false }

    func textView(_ textView: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool { false }
}
