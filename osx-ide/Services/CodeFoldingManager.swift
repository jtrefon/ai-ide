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

        setGlyphs(
            layoutManager: layoutManager,
            outGlyphs: outGlyphs,
            outProps: outProps,
            outCharIndexes: outCharIndexes,
            font: aFont,
            glyphRange: glyphRange
        )

        return count
    }

    private func setGlyphs(
        layoutManager: NSLayoutManager,
        outGlyphs: [CGGlyph],
        outProps: [NSLayoutManager.GlyphProperty],
        outCharIndexes: [Int],
        font: NSFont,
        glyphRange: NSRange
    ) {
        outGlyphs.withUnsafeBufferPointer { gPtr in
            outProps.withUnsafeBufferPointer { pPtr in
                outCharIndexes.withUnsafeBufferPointer { cPtr in
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
