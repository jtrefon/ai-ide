//
//  TerminalRenderer.swift
//  osx-ide
//
//  Created by AI Assistant on 19/12/2025.
//

import SwiftUI
import AppKit

/// Custom NSView for terminal rendering
class TerminalRendererView: NSView {
    private var screenContent: [[TerminalCharacter]] = []
    private var cursorPosition: (row: Int, column: Int) = (0, 0)
    private var font: NSFont
    private var charSize: CGSize
    private var cursorVisible = true
    private var cursorBlinkTimer: Timer?
    private var onKeyPress: ((NSEvent) -> Bool)?
    
    // MARK: - Initialization
    
    init(frame: NSRect, font: NSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)) {
        self.font = font
        self.charSize = CGSize(width: 8.0, height: 16.0) // Temporary value
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        self.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        self.charSize = CGSize(width: 8.0, height: 16.0) // Temporary value
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        self.charSize = calculateCharSize(font: font)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.isOpaque = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        needsDisplay = true
        
        // Start cursor blink timer
        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.cursorVisible.toggle()
            self?.needsDisplay = true
        }
    }
    
    deinit {
        cursorBlinkTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func updateContent(_ content: [[TerminalCharacter]], cursor: (row: Int, column: Int)) {
        screenContent = content
        cursorPosition = cursor
        needsDisplay = true
    }
    
    func setKeyPressHandler(_ handler: @escaping (NSEvent) -> Bool) {
        self.onKeyPress = handler
    }
    
    func setFont(_ newFont: NSFont) {
        font = newFont
        charSize = calculateCharSize(font: font)
        needsDisplay = true
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        // print("Renderer: draw called. Rect: \(dirtyRect)")
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Clear background
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
        
        // Draw content
        drawContent(context: context, dirtyRect: dirtyRect)
        
        // Draw cursor
        drawCursor(context: context)
    }
    
    private func drawContent(context: CGContext, dirtyRect: NSRect) {
        for (row, line) in screenContent.enumerated() {
            let y = bounds.height - CGFloat(row + 1) * charSize.height
            
            for (col, char) in line.enumerated() {
                let x = CGFloat(col) * charSize.width
                let charRect = CGRect(x: x, y: y, width: charSize.width, height: charSize.height)
                
                // Skip if outside dirty rect
                if !charRect.intersects(dirtyRect) { continue }
                
                // Draw background
                if char.getEffectiveBackgroundColor() != NSColor.black {
                    context.setFillColor(char.getEffectiveBackgroundColor().cgColor)
                    context.fill(charRect)
                }
                
                // Draw character
                if char.isVisible() {
                    let attributedString = NSAttributedString(
                        string: String(char.char),
                        attributes: [
                            .font: font,
                            .foregroundColor: char.getEffectiveForegroundColor(),
                            .underlineStyle: char.underline ? NSUnderlineStyle.single.rawValue : 0
                        ]
                    )
                    
                    attributedString.draw(in: charRect)
                }
            }
        }
    }
    
    private func drawCursor(context: CGContext) {
        guard cursorVisible else { return }
        
        let x = CGFloat(cursorPosition.column) * charSize.width
        let y = bounds.height - CGFloat(cursorPosition.row + 1) * charSize.height
        let cursorRect = CGRect(x: x, y: y, width: charSize.width, height: charSize.height)
        
        context.setFillColor(NSColor.white.cgColor)
        context.fill(cursorRect)
        
        // Draw character under cursor if exists
        if cursorPosition.row < screenContent.count &&
           cursorPosition.column < screenContent[cursorPosition.row].count {
            let char = screenContent[cursorPosition.row][cursorPosition.column]
            if char.isVisible() {
                let attributedString = NSAttributedString(
                    string: String(char.char),
                    attributes: [
                        .font: font,
                        .foregroundColor: NSColor.black
                    ]
                )
                attributedString.draw(in: cursorRect)
            }
        }
    }
    
    private func calculateCharSize(font: NSFont) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let string = "M" // Use 'M' for maximum character width
        let size = string.size(withAttributes: attributes)
        let finalSize = CGSize(width: ceil(size.width), height: ceil(size.height))
        print("Renderer: Calculated char size for font \(font.fontName): \(finalSize)")
        return finalSize
    }

    private func drawTestPattern(context: CGContext) {
        // Draw a blue border to confirm view bounds and rendering
        context.setStrokeColor(NSColor.blue.cgColor)
        context.setLineWidth(2)
        context.stroke(bounds)
        
        // Draw a generic text string manually to check font
        let testString = "Raw Render Test"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: testString, attributes: attrs)
        attrStr.draw(at: NSPoint(x: 10, y: bounds.height - 30))
    }
    
    // MARK: - Responder Chain
    
    override var acceptsFirstResponder: Bool { true }

    override var isOpaque: Bool { true }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }
    
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        needsDisplay = true
        return result
    }
    
    // MARK: - Keyboard Events
    
    override func keyDown(with event: NSEvent) {
        // Forward key events to the onKeyPress handler
        if let handler = onKeyPress {
            let handled = handler(event)
            if !handled {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

/// SwiftUI wrapper for TerminalRendererView
struct TerminalRenderer: NSViewRepresentable {
    let screenContent: [[TerminalCharacter]]
    let cursorPosition: (row: Int, column: Int)
    let onKeyPress: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> TerminalRendererView {
        let view = TerminalRendererView(frame: .zero)
        view.setKeyPressHandler(onKeyPress)
        return view
    }
    
    func updateNSView(_ nsView: TerminalRendererView, context: Context) {
        nsView.updateContent(screenContent, cursor: cursorPosition)
    }
}
