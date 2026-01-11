import Foundation
import AppKit

@MainActor
enum TestSupport {
    static var testFiles: [URL] = []

    static func uniqueForegroundColorCount(in attributed: NSAttributedString) -> Int {
        var unique: Set<String> = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, _, _ in
            guard let c = attrs[.foregroundColor] as? NSColor else { return }
            let resolved = c.usingColorSpace(.deviceRGB) ?? c
            unique.insert("\(resolved.redComponent),\(resolved.greenComponent),\(resolved.blueComponent),\(resolved.alphaComponent)")
        }
        return unique.count
    }

    static func cleanupTestFiles() {
        for file in testFiles {
            try? FileManager.default.removeItem(at: file)
        }
        testFiles.removeAll()
    }
}
