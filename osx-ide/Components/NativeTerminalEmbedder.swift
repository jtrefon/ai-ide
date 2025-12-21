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
    @Published var currentDirectory: URL?
    @Published var errorMessage: String?
    
    private var terminalView: NSTextView?
    private let shellManager = ShellManager()
    private var isCleaningUp = false
    
    override init() {
        super.init()
        shellManager.delegate = self
    }
    
    deinit {
        // Observer cleanup is handled in removeEmbedding
    }
    
    /// Embed terminal in the specified parent view
    func embedTerminal(in parentView: NSView, directory: URL? = nil) {
        let newDir = directory?.standardizedFileURL
        
        // If we already have a terminal view and process, check if we just need to change dir
        if let existingView = terminalView {
            if existingView.enclosingScrollView?.superview == parentView || existingView.superview == parentView {
                if let current = self.currentDirectory?.standardizedFileURL, let new = newDir, current.path != new.path {
                    self.currentDirectory = new
                    shellManager.sendInput("cd '\(new.path)'\n")
                }
                return
            }
        }
        
        cleanup()
        
        self.currentDirectory = newDir ?? FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        isCleaningUp = false
        
        setupTerminalView(in: parentView)
        shellManager.start(in: currentDirectory)
        
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = nil
        }
    }
    
    /// Setup terminal view
    private func setupTerminalView(in parentView: NSView) {
        parentView.subviews.forEach { $0.removeFromSuperview() }
        terminalView = nil
        parentView.wantsLayer = true
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller = LiquidGlassScroller()
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor.black
        scrollView.drawsBackground = true
        
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
        terminalView.textContainer?.lineFragmentPadding = 5
        terminalView.drawsBackground = true
        terminalView.isContinuousSpellCheckingEnabled = false
        terminalView.delegate = self
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        terminalView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
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
    }
    
    private func appendOutput(_ text: String) {
        guard !isCleaningUp, let terminalView = terminalView else { return }
        
        let processedText = processANSIEscapeSequences(text)
        guard processedText.length > 0 else { return }
        
        // Ensure UI updates are strictly on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let terminalView = self.terminalView, !self.isCleaningUp else { return }
            
            if let textStorage = terminalView.textStorage {
                textStorage.append(processedText)
            } else {
                terminalView.string += processedText.string
            }
            
            let range = NSRange(location: terminalView.string.count, length: 0)
            terminalView.setSelectedRange(range)
            terminalView.scrollRangeToVisible(range)
            terminalView.needsDisplay = true
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
                if let (newIndex, newAttributes, shouldSkip) = parseANSISequence(text, from: i) {
                    if !shouldSkip {
                        currentAttributes.merge(newAttributes) { (_, new) in new }
                    }
                    i = newIndex
                    continue
                }
            }
            
            if text[i] == "\r" {
                i = text.index(after: i)
                continue
            }
            
            let char = String(text[i])
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
    
    private func parseANSISequence(_ text: String, from start: String.Index) -> (newIndex: String.Index, attributes: [NSAttributedString.Key: Any], shouldSkip: Bool)? {
        guard start < text.endIndex, text[start] == "\u{1B}" else { return nil }
        
        var i = text.index(after: start)
        guard i < text.endIndex else { return (i, [:], false) }
        
        if text[i] == "[" {
            i = text.index(after: i)
            return parseCSISequence(text, from: i)
        } else if text[i] == "]" {
            while i < text.endIndex {
                if text[i] == "\u{07}" || (text[i] == "\u{1B}" && i < text.index(before: text.endIndex) && text[text.index(after: i)] == "\\") {
                    if text[i] == "\u{1B}" { i = text.index(after: i) }
                    i = text.index(after: i)
                    break
                }
                i = text.index(after: i)
            }
            return (i, [:], true)
        }
        
        return (i, [:], false)
    }
    
    private func parseCSISequence(_ text: String, from start: String.Index) -> (newIndex: String.Index, attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        var i = start
        var parameters: [Int] = []
        var currentParam = ""
        var attributes: [NSAttributedString.Key: Any] = [:]
        
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
                
                switch char {
                case "m":
                    attributes = applySGRParameters(parameters)
                    i = text.index(after: i)
                    return (i, attributes, false)
                default:
                    i = text.index(after: i)
                    return (i, [:], true)
                }
            }
            i = text.index(after: i)
        }
        
        return (i, [:], false)
    }
    
    private func applySGRParameters(_ parameters: [Int]) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        for param in parameters.isEmpty ? [0] : parameters {
            switch param {
            case 0: // Reset
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                attributes = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.green,
                    .paragraphStyle: paragraphStyle
                ]
            case 1: // Bold
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
            case 30...37: // Foreground
                attributes[.foregroundColor] = ansiColor(param - 30)
            case 40...47: // Background
                attributes[.backgroundColor] = ansiColor(param - 40)
            default: break
            }
        }
        return attributes
    }
    
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
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !isCleaningUp else { return false }
        
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            shellManager.sendInput("\r")
            return true
        } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            shellManager.sendInput("\u{7F}")
            return false
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            shellManager.interrupt()
            return false
        }
        
        return false
    }
    
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard !isCleaningUp, let replacementString = replacementString else { return false }
        shellManager.sendInput(replacementString)
        return true
    }
}
