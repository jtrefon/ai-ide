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

    private func subrange(_ needle: String, in container: String, within fullText: NSString, offset: Int = 0) -> NSRange {
        let containerRange = fullText.range(of: container)
        #expect(containerRange.location != NSNotFound, Comment(rawValue: "Expected to find container: \(container)"))
        let sub = (container as NSString).range(of: needle)
        #expect(sub.location != NSNotFound, Comment(rawValue: "Expected to find needle: \(needle) in container: \(container)"))
        return NSRange(location: containerRange.location + sub.location + offset, length: sub.length)
    }

    private func colorAt(_ range: NSRange, in result: NSAttributedString) -> NSColor? {
        var color: NSColor? = nil
        result.enumerateAttributes(in: range, options: []) { attrs, _, _ in
            if let c = attrs[.foregroundColor] as? NSColor { color = c }
        }
        return color
    }

    private func expectColor(_ range: NSRange, in result: NSAttributedString, equals expected: NSColor?, message: String) {
        #expect(colorAt(range, in: result) == expected, Comment(rawValue: message))
    }

    @Test func testJSONHighlighting() async throws {
        let highlighter = SyntaxHighlighter.shared
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let jsonCode = Self.jsonSample
        
        // Verify JSONModule is registered and active
        let module = LanguageModuleManager.shared.getModule(for: .json)
        #expect(module != nil, Comment(rawValue: "JSONModule should be registered in LanguageModuleManager"))
        #expect(module is JSONModule, Comment(rawValue: "Module for .json should be an instance of JSONModule"))
        
        let jsonModule = module as! JSONModule
        let result = highlighter.highlight(jsonCode, language: "json", font: font)
        let ns = jsonCode as NSString

        // Find ranges for each syntax element
        let keyRange = subrange("key", in: "\"key\": \"value\"", within: ns)
        let valueRange = subrange("value", in: "\"key\": \"value\"", within: ns)
        let numberRange = ns.range(of: "123")
        // Use value-context containers so we don't accidentally match substrings inside keys
        // (e.g., "null" inside "nullVal").
        let boolRange = subrange("true", in: ": true", within: ns)
        let nullRange = subrange("null", in: ": null", within: ns)
        let arrRange = ns.range(of: "[")
        let objRange = ns.range(of: "{")
        let arrCloseRange = ns.range(of: "]")
        let objCloseRange = ns.range(of: "}", options: .backwards)
        let commaRange = ns.range(of: ",")
        let colonRange = ns.range(of: ":")
        let quoteRange = ns.range(of: "\"") // first quote
        
        // Detailed assertions to catch the "everything is red" bug
        let keyColor = colorAt(keyRange, in: result)
        let valueColor = colorAt(valueRange, in: result)

        let expectedKey = jsonModule.highlightPalette.color(for: .key)
        let expectedString = jsonModule.highlightPalette.color(for: .string)
        let expectedNumber = jsonModule.highlightPalette.color(for: .number)
        let expectedBool = jsonModule.highlightPalette.color(for: .boolean)
        let expectedNull = jsonModule.highlightPalette.color(for: .null)
        let expectedBracket = jsonModule.highlightPalette.color(for: .bracket)
        let expectedBrace = jsonModule.highlightPalette.color(for: .brace)
        let expectedComma = jsonModule.highlightPalette.color(for: .comma)
        let expectedColon = jsonModule.highlightPalette.color(for: .colon)
        let expectedQuote = jsonModule.highlightPalette.color(for: .quote)

        let keyDesc = keyColor.map { String(describing: $0) } ?? "nil"
        let valueDesc = valueColor.map { String(describing: $0) } ?? "nil"

        #expect(keyColor == expectedKey, Comment(rawValue: "JSON Key color mismatch; got \(keyDesc)"))
        #expect(valueColor == expectedString, Comment(rawValue: "JSON String value color mismatch; got \(valueDesc)"))

        expectColor(numberRange, in: result, equals: expectedNumber, message: "JSON Number color mismatch")
        expectColor(boolRange, in: result, equals: expectedBool, message: "JSON Boolean color mismatch")
        expectColor(nullRange, in: result, equals: expectedNull, message: "JSON null color mismatch")
        expectColor(arrRange, in: result, equals: expectedBracket, message: "[ color mismatch")
        expectColor(objRange, in: result, equals: expectedBrace, message: "{ color mismatch")
        expectColor(arrCloseRange, in: result, equals: expectedBracket, message: "] color mismatch")
        expectColor(objCloseRange, in: result, equals: expectedBrace, message: "} color mismatch")
        expectColor(commaRange, in: result, equals: expectedComma, message: ", color mismatch")
        expectColor(colonRange, in: result, equals: expectedColon, message: ": color mismatch")
        expectColor(quoteRange, in: result, equals: expectedQuote, message: "quote color mismatch")
    }
}
