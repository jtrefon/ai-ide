import Testing
import Foundation
import AppKit
@testable import osx_ide

@MainActor
struct JSONHighlighterTests {
    @Test func testJSONHighlighting() async throws {
        let highlighter = SyntaxHighlighter.shared
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let jsonCode = """
        {
            "key": "value",
            "number": 123,
            "bool": true,
            "nullVal": null,
            "arr": [1, false],
            "obj": {"nested": false}
        }
        """
        
        // Verify JSONModule is registered and active
        let module = LanguageModuleManager.shared.getModule(for: .json)
        #expect(module != nil, "JSONModule should be registered in LanguageModuleManager")
        #expect(module is JSONModule, "Module for .json should be an instance of JSONModule")
        
        let jsonModule = module as! JSONModule
        let result = highlighter.highlight(jsonCode, language: "json", font: font)
        let ns = jsonCode as NSString

        func subrange(_ needle: String, in container: String, offset: Int = 0) -> NSRange {
            let containerRange = ns.range(of: container)
            #expect(containerRange.location != NSNotFound, "Expected to find container: \(container)")
            let sub = (container as NSString).range(of: needle)
            #expect(sub.location != NSNotFound, "Expected to find needle: \(needle) in container: \(container)")
            return NSRange(location: containerRange.location + sub.location + offset, length: sub.length)
        }

        // Find ranges for each syntax element
        let keyRange = subrange("key", in: "\"key\": \"value\"")
        let valueRange = subrange("value", in: "\"key\": \"value\"")
        let numberRange = ns.range(of: "123")
        // Use value-context containers so we don't accidentally match substrings inside keys
        // (e.g., "null" inside "nullVal").
        let boolRange = subrange("true", in: ": true")
        let nullRange = subrange("null", in: ": null")
        let arrRange = ns.range(of: "[")
        let objRange = ns.range(of: "{")
        let arrCloseRange = ns.range(of: "]")
        let objCloseRange = ns.range(of: "}", options: .backwards)
        let commaRange = ns.range(of: ",")
        let colonRange = ns.range(of: ":")
        let quoteRange = ns.range(of: "\"") // first quote

        func colorAt(_ range: NSRange) -> NSColor? {
            var color: NSColor? = nil
            result.enumerateAttributes(in: range, options: []) { attrs, _, _ in
                if let c = attrs[.foregroundColor] as? NSColor { color = c }
            }
            return color
        }
        
        // Detailed assertions to catch the "everything is red" bug
        let keyColor = colorAt(keyRange)
        let valueColor = colorAt(valueRange)

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

        #expect(keyColor == expectedKey, "JSON Key color mismatch; got \(keyDesc)")
        #expect(valueColor == expectedString, "JSON String value color mismatch; got \(valueDesc)")

        #expect(colorAt(numberRange) == expectedNumber, "JSON Number color mismatch")
        #expect(colorAt(boolRange) == expectedBool, "JSON Boolean color mismatch")
        #expect(colorAt(nullRange) == expectedNull, "JSON null color mismatch")
        #expect(colorAt(arrRange) == expectedBracket, "[ color mismatch")
        #expect(colorAt(objRange) == expectedBrace, "{ color mismatch")
        #expect(colorAt(arrCloseRange) == expectedBracket, "] color mismatch")
        #expect(colorAt(objCloseRange) == expectedBrace, "} color mismatch")
        #expect(colorAt(commaRange) == expectedComma, ", color mismatch")
        #expect(colorAt(colonRange) == expectedColon, ": color mismatch")
        #expect(colorAt(quoteRange) == expectedQuote, "quote color mismatch")
    }
}
