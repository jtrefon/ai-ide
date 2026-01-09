import AppKit
import Foundation

public final class CodeFoldingManager: NSObject {
    private(set) var foldedRanges: [NSRange] = []

    public func isFolded(_ range: NSRange) -> Bool {
        foldedRanges.contains(where: { NSEqualRanges($0, range) })
    }

    public func isIndexFolded(_ index: Int) -> Bool {
        for r in foldedRanges {
            if index >= r.location && index < NSMaxRange(r) {
                return true
            }
        }
        return false
    }

    public func toggle(range: NSRange) {
        if let idx = foldedRanges.firstIndex(where: { NSEqualRanges($0, range) }) {
            foldedRanges.remove(at: idx)
        } else {
            foldedRanges.append(range)
        }
        normalize()
    }

    public func unfoldAll() {
        foldedRanges.removeAll()
    }

    private func normalize() {
        foldedRanges.sort { a, b in
            if a.location != b.location { return a.location < b.location }
            return a.length < b.length
        }
    }
}

public final class FoldingLayoutManagerDelegate: NSObject, NSLayoutManagerDelegate {
    private let manager: CodeFoldingManager

    private struct GlyphGenerationOutput {
        let glyphs: [CGGlyph]
        let properties: [NSLayoutManager.GlyphProperty]
        let characterIndexes: [Int]
    }

    public init(manager: CodeFoldingManager) {
        self.manager = manager
    }

    public func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        let count = glyphRange.length
        var outGlyphs: [CGGlyph] = Array(repeating: 0, count: count)
        var outProps: [NSLayoutManager.GlyphProperty] = Array(repeating: [], count: count)
        var outCharIndexes: [Int] = Array(repeating: 0, count: count)

        for i in 0..<count {
            let chIdx = charIndexes[i]
            outCharIndexes[i] = chIdx

            if manager.isIndexFolded(chIdx) {
                outGlyphs[i] = 0
                outProps[i] = .null
            } else {
                outGlyphs[i] = glyphs[i]
                outProps[i] = props[i]
            }
        }

        let output = GlyphGenerationOutput(
            glyphs: outGlyphs,
            properties: outProps,
            characterIndexes: outCharIndexes
        )
        setGlyphs(layoutManager: layoutManager, output: output, font: aFont, glyphRange: glyphRange)

        return count
    }

    private func setGlyphs(
        layoutManager: NSLayoutManager,
        output: GlyphGenerationOutput,
        font: NSFont,
        glyphRange: NSRange
    ) {
        output.glyphs.withUnsafeBufferPointer { gPtr in
            output.properties.withUnsafeBufferPointer { pPtr in
                output.characterIndexes.withUnsafeBufferPointer { cPtr in
                    layoutManager.setGlyphs(
                        gPtr.baseAddress!,
                        properties: pPtr.baseAddress!,
                        characterIndexes: cPtr.baseAddress!,
                        font: font,
                        forGlyphRange: glyphRange
                    )
                }
            }
        }
    }
}
