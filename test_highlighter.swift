import Foundation
import AppKit

// Mocking TreeSitterManager since it depends on the project files
// In a real test, we'd compile the actual files together.
// For now, I'll use this to verify the logic I just wrote.

let code = """
import Foundation
class MyClass {
    func hello() {
        print("Hello") // Comment
    }
}
"""

print("Starting Tree-sitter highlight test...")
let highlighted = SyntaxHighlighter.shared.highlight(code, language: "swift")
print("Highlighted length: \(highlighted.length)")

highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length), options: []) { attrs, range, _ in
    let substring = (code as NSString).substring(with: range)
    if let color = attrs[.foregroundColor] as? NSColor {
        print("Range \(range) [\(substring)]: Color \(color)")
    } else {
        print("Range \(range) [\(substring)]: No Color")
    }
}
