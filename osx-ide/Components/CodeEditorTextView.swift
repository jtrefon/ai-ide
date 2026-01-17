import AppKit

@MainActor
final class CodeEditorTextView: NSTextView {
    let foldingManager = CodeFoldingManager()
    private lazy var foldingDelegate = FoldingLayoutManagerDelegate(manager: foldingManager)

    func configureFolding() {
        layoutManager?.delegate = foldingDelegate
    }

    @IBAction func toggleFoldAtCursor(_ sender: Any?) {
        let cursor = selectedRange.location
        let range = CodeFoldingRangeFinder.foldRange(at: cursor, in: string)
        guard let range else { return }

        foldingManager.toggle(range: range)
        reflowForFoldingChange()
    }

    @IBAction func unfoldAll(_ sender: Any?) {
        foldingManager.unfoldAll()
        reflowForFoldingChange()
    }

    private func reflowForFoldingChange() {
        guard let layoutManager else { return }
        guard let textContainer else { return }
        layoutManager.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: (string as NSString).length),
            actualCharacterRange: nil
        )
        layoutManager.ensureLayout(for: textContainer)

        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    // MARK: - Multi-cursor (VS Code style)

    @IBAction func addNextOccurrence(_ sender: Any?) {
        let ns = string as NSString

        let existingRanges = selectedRanges
            .compactMap { ($0 as? NSValue)?.rangeValue }
            .sorted(by: { $0.location < $1.location })

        let primary = existingRanges.last ?? selectedRange
        let needleRange: NSRange
        if primary.length > 0 {
            needleRange = primary
        } else {
            guard let word = wordRange(at: primary.location, in: ns) else { return }
            needleRange = word
        }

        let needle = ns.substring(with: needleRange)
        let fromIndex = max(
            NSMaxRange(needleRange),
            NSMaxRange(existingRanges.last ?? needleRange)
        )
        guard let next = MultiCursorUtilities.nextOccurrenceRange(
            text: string,
            needle: needle,
            fromIndex: fromIndex
        ) else { return }

        var newSelections = existingRanges
        newSelections.append(next)
        setSelectedRanges(
            uniqueSorted(newSelections).map { NSValue(range: $0) },
            affinity: .downstream,
            stillSelecting: false
        )
        scrollRangeToVisible(next)
    }

    @IBAction func addCursorAbove(_ sender: Any?) {
        addCursorVertically(direction: .up)
    }

    @IBAction func addCursorBelow(_ sender: Any?) {
        addCursorVertically(direction: .down)
    }

    private func addCursorVertically(direction: MultiCursorVerticalDirection) {
        let existingRanges = selectedRanges
            .compactMap { ($0 as? NSValue)?.rangeValue }
            .sorted(by: { $0.location < $1.location })

        let base = existingRanges.isEmpty ? [selectedRange] : existingRanges
        var out = existingRanges

        for range in base {
            let caret = range.location
            if let moved = MultiCursorUtilities.caretMovedVertically(text: string, caret: caret, direction: direction) {
                out.append(NSRange(location: moved, length: 0))
            }
        }

        setSelectedRanges(uniqueSorted(out).map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
    }

    private func uniqueSorted(_ ranges: [NSRange]) -> [NSRange] {
        var seen = Set<String>()
        let sorted = ranges.sorted { left, right in
            if left.location != right.location { return left.location < right.location }
            return left.length < right.length
        }
        var out: [NSRange] = []
        for range in sorted {
            let key = "\(range.location):\(range.length)"
            if seen.insert(key).inserted {
                out.append(range)
            }
        }
        return out
    }

    private func wordRange(at index: Int, in ns: NSString) -> NSRange? {
        let safe = max(0, min(index, ns.length))
        if ns.length == 0 { return nil }

        func isWord(_ characterString: String) -> Bool {
            guard let scalar = characterString.unicodeScalars.first else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || characterString == "_"
        }

        var start = safe
        while start > 0 {
            let ch = ns.substring(with: NSRange(location: start - 1, length: 1))
            if !isWord(ch) { break }
            start -= 1
        }

        var end = safe
        while end < ns.length {
            let ch = ns.substring(with: NSRange(location: end, length: 1))
            if !isWord(ch) { break }
            end += 1
        }

        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
