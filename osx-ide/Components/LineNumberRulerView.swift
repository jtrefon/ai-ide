import AppKit

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let font: NSFont
    private let textColor: NSColor
    private let backgroundColor: NSColor

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        self.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        self.textColor = NSColor.secondaryLabelColor
        self.backgroundColor = NSColor.controlBackgroundColor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 50
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return
        }

        backgroundColor.setFill()
        rect.fill()

        let relativePoint = convert(NSZeroPoint, from: textView)
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)

        let string = textView.string as NSString
        let firstCharIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)

        var lineNumber = 1
        if firstCharIndex > 0 {
            lineNumber = string.substring(to: firstCharIndex).reduce(into: 1) { acc, ch in
                if ch == "\n" { acc += 1 }
            }
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            var lineStart: Int = 0
            var lineEnd: Int = 0
            string.getLineStart(&lineStart, end: &lineEnd, contentsEnd: nil, for: NSRange(location: charIndex, length: 0))

            let charRange = NSRange(location: lineStart, length: max(0, lineEnd - lineStart))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)
            lineRect.origin.x += relativePoint.x
            lineRect.origin.y += relativePoint.y

            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attrs)
            let y = lineRect.minY + (lineRect.height - labelSize.height) / 2
            let x = ruleThickness - 6 - labelSize.width
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

            let nextGlyphIndex = NSMaxRange(lineGlyphRange)
            glyphIndex = nextGlyphIndex > glyphIndex ? nextGlyphIndex : (glyphIndex + 1)
            lineNumber += 1
        }
    }
}
