import Testing
import Foundation
import AppKit
@testable import osx_ide

@MainActor
struct JSONHighlighterTests {

    private static let jsonSample = """
        {
            \"key\": \"value\",
            \"number\": 123,
            \"bool\": true,
            \"nullVal\": null,
            \"arr\": [1, false],
            \"obj\": {\"nested\": false}
        }
        """

    private func subrange(
        _ needle: String,
        in container: String,
        within fullText: NSString,
        offset: Int = 0
    ) -> NSRange {
        let containerRange = fullText.range(of: container)
        #expect(
            containerRange.location != NSNotFound,
            Comment(rawValue: "Expected to find container: \(container)")
        )
        let sub = (container as NSString).range(of: needle)
        #expect(
            sub.location != NSNotFound,
            Comment(rawValue: "Expected to find needle: \(needle) in container: \(container)")
        )
        return NSRange(location: containerRange.location + sub.location + offset, length: sub.length)
    }

    private func colorAt(_ range: NSRange, in result: NSAttributedString) -> NSColor? {
        var color: NSColor?
        result.enumerateAttributes(in: range, options: []) { attrs, _, _ in
            if let foregroundColor = attrs[.foregroundColor] as? NSColor {
                color = foregroundColor
            }
        }
        return color
    }

    private func expectColor(
        _ range: NSRange,
        in result: NSAttributedString,
        equals expected: NSColor?,
        message: String
    ) {
        #expect(colorAt(range, in: result) == expected, Comment(rawValue: message))
    }

    @Test func testJSONHighlighting() async throws {
        let highlighter = SyntaxHighlighter.shared
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let jsonCode = Self.jsonSample

        // Verify JSONModule is registered and active
        let module = LanguageModuleManager.shared.getModule(for: .json)
        #expect(
            module != nil,
            Comment(rawValue: "JSONModule should be registered in LanguageModuleManager")
        )
        #expect(
            module is JSONModule,
            Comment(rawValue: "Module for .json should be an instance of JSONModule")
        )

        guard let jsonModule = module as? JSONModule else {
            #expect(false, Comment(rawValue: "Module for .json should be an instance of JSONModule"))
            return
        }
        let result = highlighter.highlight(jsonCode, language: "json", font: font)
        let sourceText = jsonCode as NSString

        struct ExpectedColors {
            let key: NSColor?
            let string: NSColor?
            let number: NSColor?
            let boolean: NSColor?
            let null: NSColor?
            let bracket: NSColor?
            let brace: NSColor?
            let comma: NSColor?
            let colon: NSColor?
            let quote: NSColor?
        }

        let expected = ExpectedColors(
            key: jsonModule.highlightPalette.color(for: .key),
            string: jsonModule.highlightPalette.color(for: .string),
            number: jsonModule.highlightPalette.color(for: .number),
            boolean: jsonModule.highlightPalette.color(for: .boolean),
            null: jsonModule.highlightPalette.color(for: .null),
            bracket: jsonModule.highlightPalette.color(for: .bracket),
            brace: jsonModule.highlightPalette.color(for: .brace),
            comma: jsonModule.highlightPalette.color(for: .comma),
            colon: jsonModule.highlightPalette.color(for: .colon),
            quote: jsonModule.highlightPalette.color(for: .quote)
        )

        // Find ranges for each syntax element
        let keyRange = subrange("key", in: "\"key\": \"value\"", within: sourceText)
        let valueRange = subrange("value", in: "\"key\": \"value\"", within: sourceText)
        let numberRange = sourceText.range(of: "123")
        // Use value-context containers so we don't accidentally match substrings inside keys
        // (e.g., "null" inside "nullVal").
        let boolRange = subrange("true", in: ": true", within: sourceText)
        let nullRange = subrange("null", in: ": null", within: sourceText)
        let arrRange = sourceText.range(of: "[")
        let objRange = sourceText.range(of: "{")
        let arrCloseRange = sourceText.range(of: "]")
        let objCloseRange = sourceText.range(of: "}", options: .backwards)
        let commaRange = sourceText.range(of: ",")
        let colonRange = sourceText.range(of: ":")
        let quoteRange = sourceText.range(of: "\"") // first quote

        // Detailed assertions to catch the "everything is red" bug
        let keyColor = colorAt(keyRange, in: result)
        let valueColor = colorAt(valueRange, in: result)

        let keyDesc = keyColor.map { String(describing: $0) } ?? "nil"
        let valueDesc = valueColor.map { String(describing: $0) } ?? "nil"

        #expect(
            keyColor == expected.key,
            Comment(rawValue: "JSON Key color mismatch; got \(keyDesc)")
        )
        #expect(
            valueColor == expected.string,
            Comment(rawValue: "JSON String value color mismatch; got \(valueDesc)")
        )

        expectColor(numberRange, in: result, equals: expected.number, message: "JSON Number color mismatch")
        expectColor(boolRange, in: result, equals: expected.boolean, message: "JSON Boolean color mismatch")
        expectColor(nullRange, in: result, equals: expected.null, message: "JSON null color mismatch")
        expectColor(arrRange, in: result, equals: expected.bracket, message: "[ color mismatch")
        expectColor(objRange, in: result, equals: expected.brace, message: "{ color mismatch")
        expectColor(arrCloseRange, in: result, equals: expected.bracket, message: "] color mismatch")
        expectColor(objCloseRange, in: result, equals: expected.brace, message: "} color mismatch")
        expectColor(commaRange, in: result, equals: expected.comma, message: ", color mismatch")
        expectColor(colonRange, in: result, equals: expected.colon, message: ": color mismatch")
        expectColor(quoteRange, in: result, equals: expected.quote, message: "quote color mismatch")
    }
}
