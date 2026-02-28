import Testing
import AppKit
@testable import osx_ide

@MainActor
struct SyntaxHighlighterTests {
    private func colorAt(_ range: NSRange, in result: NSAttributedString) -> NSColor? {
        guard range.location != NSNotFound else { return nil }
        var color: NSColor?
        result.enumerateAttributes(in: range, options: []) { attrs, _, _ in
            color = attrs[.foregroundColor] as? NSColor
        }
        return color
    }

    private func range(of value: String, in text: String) -> NSRange {
        (text as NSString).range(of: value)
    }

    private func expectedColor(language: CodeLanguage, role: HighlightRole, fallback: NSColor) -> NSColor {
        LanguageKeywordRepository.tokenColor(for: language, role: role) ?? fallback
    }

    @Test func testKeywordProtectionInsideStringAndCommentAcrossLanguages() async throws {
        let highlighter = SyntaxHighlighter.shared

        let javascriptCode = "const message = \"if return\"; // while switch"
        let javascriptResult = highlighter.highlight(javascriptCode, language: "javascript")
        #expect(colorAt(range(of: "if", in: javascriptCode), in: javascriptResult) == expectedColor(language: .javascript, role: .string, fallback: .systemRed))
        #expect(colorAt(range(of: "return", in: javascriptCode), in: javascriptResult) == expectedColor(language: .javascript, role: .string, fallback: .systemRed))
        #expect(colorAt(range(of: "while", in: javascriptCode), in: javascriptResult) == expectedColor(language: .javascript, role: .comment, fallback: .systemGreen))

        let typeScriptCode = "const status = 'interface type'; // readonly private"
        let typeScriptResult = highlighter.highlight(typeScriptCode, language: "typescript")
        #expect(colorAt(range(of: "interface", in: typeScriptCode), in: typeScriptResult) == expectedColor(language: .typescript, role: .string, fallback: .systemRed))
        #expect(colorAt(range(of: "type", in: typeScriptCode), in: typeScriptResult) == expectedColor(language: .typescript, role: .string, fallback: .systemRed))
        #expect(colorAt(range(of: "readonly", in: typeScriptCode), in: typeScriptResult) == expectedColor(language: .typescript, role: .comment, fallback: .systemGreen))

        let swiftCode = "let message = \"if return\" // guard"
        let swiftResult = highlighter.highlight(swiftCode, language: "swift")
        #expect(colorAt(range(of: "if", in: swiftCode), in: swiftResult) == .systemRed)
        #expect(colorAt(range(of: "return", in: swiftCode), in: swiftResult) == .systemRed)
        #expect(colorAt(range(of: "guard", in: swiftCode), in: swiftResult) == .systemGreen)

        let pythonCode = "message = \"if is\"\n# while"
        let pythonResult = highlighter.highlight(pythonCode, language: "python")
        #expect(colorAt(range(of: "if", in: pythonCode), in: pythonResult) == .systemRed)
        #expect(colorAt(range(of: "is", in: pythonCode), in: pythonResult) == .systemRed)
        #expect(colorAt(range(of: "while", in: pythonCode), in: pythonResult) == .systemGreen)
    }

    @Test func testDisablingHighlightCapabilityRemovesHighlightModule() async throws {
        let manager = LanguageModuleManager.shared
        defer {
            manager.toggleCapability(.highlight, for: .javascript, enabled: true)
        }

        manager.toggleCapability(.highlight, for: .javascript, enabled: false)
        let module = manager.getHighlightModule(for: .javascript)
        #expect(module == nil)
    }

    @Test func testSyntaxHighlighter() async throws {
        let highlighter = SyntaxHighlighter.shared

        // Test Swift highlighting
        let swiftCode = """
        import Foundation

        class MyClass {
            let name: String

            init(name: String) {
                self.name = name
            }

            func greet() -> String {
                return "Hello, " + name + "!"
            }
        }
        """

        let swiftResult = highlighter.highlight(swiftCode, language: "swift")
        #expect(!swiftResult.string.isEmpty, "Highlighted result should not be empty")
        #expect(swiftResult.string == swiftCode, "Result should contain original code")

        // Verify that highlighting produced at least one non-default foreground color.
        var foundAnyHighlight = false
        swiftResult.enumerateAttributes(in: NSRange(location: 0, length: swiftResult.length), options: []) { attrs, _, _ in
            if let color = attrs[.foregroundColor] as? NSColor, color != NSColor.labelColor {
                foundAnyHighlight = true
            }
        }
        #expect(foundAnyHighlight, "Expected at least one highlight to be applied")

        // Test Python highlighting (should still return plain text with base styling)
        let pythonCode = """
        def hello_world():
            name = "World"
            print(f"Hello, {name}!")

        if __name__ == "__main__":
            hello_world()
        """

        let pythonResult = highlighter.highlight(pythonCode, language: "python")
        #expect(!pythonResult.string.isEmpty, "Python result should not be empty")
        #expect(pythonResult.string == pythonCode, "Python result should contain original code")

        // Test JavaScript highlighting (should still return plain text with base styling)
        let jsCode = """
        function greet(name) {
            return `Hello, ${name}!`;
        }

        const message = greet("World");
        console.log(message);
        """

        let jsResult = highlighter.highlight(jsCode, language: "javascript")
        #expect(!jsResult.string.isEmpty, "JavaScript result should not be empty")
        #expect(jsResult.string == jsCode, "JavaScript result should contain original code")

        #expect(LanguageModuleManager.shared.getHighlightModule(for: .unknown) == nil)
    }

    @Test func testHighlightingPerformance() async throws {
        let highlighter = SyntaxHighlighter.shared

        // Generate a large code sample
        var largeCode = """
        import Foundation

        class LargeClass {
        """

        for methodIndex in 0..<100 {
            largeCode += """

            func method\(methodIndex)() -> Int {
                return \(methodIndex)
            }
            """
        }

        largeCode += """
        }
        """

        // Measure highlighting performance
        let startTime = ContinuousClock.now
        _ = highlighter.highlight(largeCode, language: "swift")
        let endTime = ContinuousClock.now

        let duration = startTime.duration(to: endTime)
        #expect(duration < .seconds(1), "Highlighting should complete within 1 second")
    }

    @Test func testTypeScriptAndTSXShareHighlightingBehavior() async throws {
        let highlighter = SyntaxHighlighter.shared
        let code = """
        import React from 'react'
        interface PasswordRecoveryProps {
            onPasswordRecovery?: (email: string) => void
        }
        const isSubmitting = false
        // Simulate API call
        if (!email) {
            return false
        }
        """

        let tsResult = highlighter.highlight(code, language: "typescript")
        let tsxResult = highlighter.highlight(code, language: "tsx")

        let keywordColor = expectedColor(language: .typescript, role: .keyword, fallback: .systemBlue)
        let typeColor = expectedColor(language: .typescript, role: .type, fallback: .systemPurple)
        let boolColor = expectedColor(language: .typescript, role: .boolean, fallback: .systemOrange)
        let stringColor = expectedColor(language: .typescript, role: .string, fallback: .systemRed)
        let commentColor = expectedColor(language: .typescript, role: .comment, fallback: .systemGreen)

        #expect(colorAt(range(of: "import", in: code), in: tsResult) == keywordColor)
        #expect(colorAt(range(of: "interface", in: code), in: tsResult) == keywordColor)
        #expect(colorAt(range(of: "const", in: code), in: tsResult) == keywordColor)
        #expect(colorAt(range(of: "if", in: code), in: tsResult) == keywordColor)
        #expect(colorAt(range(of: "return", in: code), in: tsResult) == keywordColor)
        #expect(colorAt(range(of: "string", in: code), in: tsResult) == typeColor)
        #expect(colorAt(range(of: "false", in: code), in: tsResult) == boolColor)
        #expect(colorAt(range(of: "'react'", in: code), in: tsResult) == stringColor)
        #expect(colorAt(range(of: "// Simulate API call", in: code), in: tsResult) == commentColor)

        #expect(colorAt(range(of: "import", in: code), in: tsxResult) == keywordColor)
        #expect(colorAt(range(of: "interface", in: code), in: tsxResult) == keywordColor)
        #expect(colorAt(range(of: "string", in: code), in: tsxResult) == typeColor)
        #expect(colorAt(range(of: "false", in: code), in: tsxResult) == boolColor)
    }
}
