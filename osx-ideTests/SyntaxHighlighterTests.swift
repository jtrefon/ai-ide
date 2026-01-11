import Testing
import AppKit
@testable import osx_ide

@MainActor
struct SyntaxHighlighterTests {

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

        // Test fallback for unknown language
        let unknownCode = "just plain text"
        let unknownResult = highlighter.highlight(unknownCode, language: "unknown")
        #expect(!unknownResult.string.isEmpty, "Unknown result should not be empty")
        #expect(unknownResult.string == unknownCode, "Unknown result should contain original code")
    }

    @Test func testHighlightingPerformance() async throws {
        let highlighter = SyntaxHighlighter.shared

        // Generate a large code sample
        var largeCode = """
        import Foundation

        class LargeClass {
        """

        for i in 0..<100 {
            largeCode += """

            func method\(i)() -> Int {
                return \(i)
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
}
