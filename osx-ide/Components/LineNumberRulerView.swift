import AppKit
import SwiftUI

/// Modern macOS v26 line number ruler with enhanced performance and liquid glass styling
final class ModernLineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var font: NSFont
    private let textColor: NSColor
    private let backgroundColor: NSColor
    private let selectionColor: NSColor
    private let currentLineColor: NSColor

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        // Enhanced typography for macOS v26
        self.font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        self.textColor = NSColor.secondaryLabelColor
        self.backgroundColor = NSColor.clear // Transparent for liquid glass
        self.selectionColor = NSColor.systemBlue.withAlphaComponent(0.1)
        self.currentLineColor = NSColor.systemBlue.withAlphaComponent(0.05)
        
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 50
        
        // Modern styling for macOS v26
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func updateFont(_ font: NSFont?) {
        guard let font else { return }
        guard self.font != font else { return }
        self.font = font
        needsDisplay = true
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    nonisolated static func startingLineNumber(string: NSString, firstCharIndex: Int) -> Int {
        guard firstCharIndex > 0 else { return 1 }

        // IMPORTANT: NSTextView / NSLayoutManager indices are UTF-16 (NSString) based.
        // Do not mix Swift String.count (grapheme clusters) with NSRange locations.
        var count = 1
        var pos = 0
        while pos < firstCharIndex {
            let r = string.lineRange(for: NSRange(location: pos, length: 0))
            let next = NSMaxRange(r)
            guard next > pos else { break }
            if next <= firstCharIndex {
                count += 1
            }
            pos = next
        }
        return count
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, 
              let layoutManager = textView.layoutManager, 
              let textContainer = textView.textContainer else {
            return
        }

        // Draw transparent background for liquid glass effect
        backgroundColor.setFill()
        rect.fill()

        let relativePoint = convert(NSZeroPoint, from: textView)
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)

        let string = textView.string as NSString
        let firstCharIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)

        let lineNumber = Self.startingLineNumber(string: string, firstCharIndex: firstCharIndex)
        let context = DrawLineNumbersContext(
            textView: textView,
            string: string,
            layoutManager: layoutManager,
            textContainer: textContainer,
            glyphRange: glyphRange,
            relativePoint: relativePoint,
            startingLineNumber: lineNumber
        )
        drawLineNumbers(context: context)
    }

    private struct DrawLineNumbersContext {
        let textView: NSTextView
        let string: NSString
        let layoutManager: NSLayoutManager
        let textContainer: NSTextContainer
        let glyphRange: NSRange
        let relativePoint: NSPoint
        let startingLineNumber: Int
    }

    private func drawLineNumbers(context: DrawLineNumbersContext) {
        var lineNumber = context.startingLineNumber

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        var glyphIndex = context.glyphRange.location
        while glyphIndex < NSMaxRange(context.glyphRange) {
            let charIndex = context.layoutManager.characterIndexForGlyph(at: glyphIndex)
            var lineStart: Int = 0
            var lineEnd: Int = 0
            context.string.getLineStart(
                &lineStart, 
                end: &lineEnd, 
                contentsEnd: nil, 
                for: NSRange(location: charIndex, length: 0)
            )

            let charRange = NSRange(location: lineStart, length: max(0, lineEnd - lineStart))
            let lineGlyphRange = context.layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            var lineRect = context.layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: context.textContainer)
            lineRect.origin.x += context.relativePoint.x
            lineRect.origin.y += context.relativePoint.y

            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attrs)
            let y = lineRect.minY + (lineRect.height - labelSize.height) / 2
            let x = ruleThickness - 6 - labelSize.width

            if charIndex == context.textView.selectedRange.location {
                let highlightRect = NSRect(x: 0, y: lineRect.minY, width: ruleThickness, height: lineRect.height)
                selectionColor.setFill()
                highlightRect.fill()
            }

            label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

            let nextGlyphIndex = NSMaxRange(lineGlyphRange)
            glyphIndex = nextGlyphIndex > glyphIndex ? nextGlyphIndex : (glyphIndex + 1)
            lineNumber += 1
        }
    }
    
    // Modern macOS v26 compatibility methods
    override var wantsUpdateLayer: Bool {
        return true
    }
    
    override func updateLayer() {
        super.updateLayer()
        // Enhanced layer setup for liquid glass effect
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
