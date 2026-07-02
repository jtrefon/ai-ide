import AppKit

@MainActor
final class CodeEditorTextView: NSTextView {
    let foldingManager = CodeFoldingManager()
    private lazy var foldingDelegate = FoldingLayoutManagerDelegate(manager: foldingManager)
    private var ghostPresentation: InlineSuggestionPresentation?
    private var ghostRange: NSRange?

    private static let ghostAttributeKey = NSAttributedString.Key("com.osxide.ghostSuggestion")

    var hasInlineSuggestion: Bool {
        ghostPresentation != nil
    }

    var inlineSuggestionText: String? {
        ghostPresentation?.suggestionText
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
    }

    func configureFolding() {
        layoutManager?.delegate = foldingDelegate
    }

    override func layout() {
        super.layout()
    }

    func updateGhostSuggestion(_ presentation: InlineSuggestionPresentation) {
        clearGhostTextFromStorage()

        ghostPresentation = presentation
        let text = String(presentation.suggestionText.prefix(600))
        let cursor = selectedRange.location

        guard let textStorage, let layoutManager else { return }

        let insertionRange = NSRange(location: cursor, length: 0)
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: insertionRange, with: text)

        let newGhostRange = NSRange(location: cursor, length: (text as NSString).length)
        textStorage.addAttribute(Self.ghostAttributeKey, value: true, range: newGhostRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.placeholderTextColor, range: newGhostRange)
        if let font {
            textStorage.addAttribute(.font, value: font, range: newGhostRange)
        }
        textStorage.endEditing()

        ghostRange = newGhostRange
        needsDisplay = true
    }

    func clearInlineSuggestion() {
        clearGhostTextFromStorage()
        ghostPresentation = nil
    }

    private func clearGhostTextFromStorage() {
        guard let range = ghostRange, let textStorage else { return }
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: "")
        textStorage.endEditing()
        ghostRange = nil
    }

    @discardableResult
    func acceptInlineSuggestion() -> Bool {
        guard let presentation = ghostPresentation, !presentation.suggestionText.isEmpty else {
            return false
        }
        guard let range = ghostRange, let textStorage else { return false }

        textStorage.removeAttribute(Self.ghostAttributeKey, range: range)
        textStorage.removeAttribute(.foregroundColor, range: range)
        textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)

        let newCursor = range.location + range.length
        setSelectedRange(NSRange(location: newCursor, length: 0))

        ghostPresentation = nil
        ghostRange = nil
        return true
    }

    // MARK: - Text Storage Delegate

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard let ghostRange else { return }

        let ghostEnd = ghostRange.location + ghostRange.length
        let editEnd = editedRange.location + editedRange.length

        if editedRange.location >= ghostEnd {
            return
        }

        if editEnd <= ghostRange.location {
            let newLocation = ghostRange.location + delta
            self.ghostRange = NSRange(location: newLocation, length: ghostRange.length)
            return
        }

        clearGhostTextFromStorage()
        ghostPresentation = nil
    }

    // MARK: - Folding (unchanged)

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
            .compactMap { $0.rangeValue }
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
            .compactMap { $0.rangeValue }
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
