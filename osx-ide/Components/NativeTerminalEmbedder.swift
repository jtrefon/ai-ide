//
//  NativeTerminalEmbedder.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import SwiftUI
import AppKit
import Foundation

/// Reliable terminal UI implementation that integrates with ShellManager
@MainActor
class NativeTerminalEmbedder: NSObject, ObservableObject {
    typealias TerminalTextView = NativeTerminalTextView

    @Published var currentDirectory: URL?
    @Published var errorMessage: String?

    var terminalView: NSTextView?
    let shellManager: ShellManaging
    var isCleaningUp = false

    var fontSize: CGFloat = 12
    var fontFamily: String = "SF Mono"

    let eventBus: EventBusProtocol
    
    // Virtual screen buffer for proper terminal emulation
    var screenBuffer: TerminalScreenBuffer?
    var screenRenderer: TerminalScreenRenderer?

    init(shellManager: ShellManaging = ShellManager(), eventBus: EventBusProtocol) {
        self.shellManager = shellManager
        self.eventBus = eventBus
        super.init()
        shellManager.delegate = self
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
        
        // Schedule initial resize after view is laid out
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay for layout
            self?.handleResize(in: parentView)
        }
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
        resetContainerView(parentView)

        let scrollView = makeTerminalScrollView()
        let terminalTextView = makeTerminalTextView()
        applyDefaultTypingAttributes(to: terminalTextView)
        embed(scrollView: scrollView, terminalView: terminalTextView, in: parentView)
        resetTerminalState(for: terminalTextView)
    }

    private func resetContainerView(_ parentView: NSView) {
        parentView.subviews.forEach { $0.removeFromSuperview() }
        terminalView = nil
        parentView.wantsLayer = true
    }

    private func makeTerminalScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor.black
        scrollView.drawsBackground = true
        return scrollView
    }

    private func makeTerminalTextView() -> TerminalTextView {
        let terminalView = TerminalTextView()
        terminalView.inputDelegate = self
        terminalView.isEditable = true
        terminalView.isSelectable = true
        terminalView.isRichText = false
        terminalView.usesRuler = false
        terminalView.font = resolveFont(size: fontSize, family: fontFamily)
        terminalView.backgroundColor = NSColor.black
        terminalView.textColor = NSColor.green
        terminalView.insertionPointColor = NSColor.green
        terminalView.alignment = .left
        terminalView.isVerticallyResizable = true
        terminalView.isHorizontallyResizable = true
        terminalView.textContainer?.lineFragmentPadding = 5
        terminalView.drawsBackground = true
        terminalView.isContinuousSpellCheckingEnabled = false
        terminalView.delegate = self
        terminalView.setAccessibilityIdentifier("TerminalTextView")
        return terminalView
    }

    func forwardTerminalInput(_ text: String) {
        shellManager.sendInput(text)
    }

    func handleTerminalCommand(_ selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            shellManager.sendInput("\n")
            return true
        }
        if selector == #selector(NSResponder.deleteBackward(_:)) {
            shellManager.sendInput("\u{7F}")
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            shellManager.interrupt()
            return true
        }
        return false
    }

    private func applyDefaultTypingAttributes(to terminalView: TerminalTextView) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        terminalView.typingAttributes = [
            .font: resolveFont(size: fontSize, family: fontFamily),
            .foregroundColor: NSColor.green,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func embed(scrollView: NSScrollView, terminalView: TerminalTextView, in parentView: NSView) {
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
    }

    private func resetTerminalState(for terminalView: TerminalTextView) {
        // Initialize screen buffer and renderer
        screenBuffer = TerminalScreenBuffer(rows: 24, columns: 80)
        screenRenderer = TerminalScreenRenderer(textView: terminalView) { [weak self] size, family in
            self?.resolveFont(size: size, family: family) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
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

    /// Handle terminal resize
    func handleResize(in view: NSView) {
        guard terminalView != nil else { return }
        
        let font = resolveFont(size: fontSize, family: fontFamily)
        let charWidth = font.maximumAdvancement.width
        let charHeight = font.boundingRectForFont.height
        
        let viewWidth = view.bounds.width
        let viewHeight = view.bounds.height
        
        let columns = max(1, Int(viewWidth / charWidth))
        let rows = max(1, Int(viewHeight / charHeight))
        
        // Resize both the PTY and the screen buffer
        screenBuffer?.resize(rows: rows, columns: columns)
        shellManager.resize(rows: rows, columns: columns)
    }
}
