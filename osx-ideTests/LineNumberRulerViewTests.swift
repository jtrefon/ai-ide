import Testing
import Foundation
import AppKit
@testable import osx_ide

@MainActor
struct LineNumberRulerViewTests {

    @Test func testStartingLineNumberCountsLinesUpToFirstCharIndex() async throws {
        let s = "a\nb\nc\n" as NSString

        #expect(ModernLineNumberRulerView.startingLineNumber(string: s, firstCharIndex: 0) == 1)
        #expect(ModernLineNumberRulerView.startingLineNumber(string: s, firstCharIndex: 1) == 1)
        #expect(ModernLineNumberRulerView.startingLineNumber(string: s, firstCharIndex: 2) == 2)
        #expect(ModernLineNumberRulerView.startingLineNumber(string: s, firstCharIndex: 4) == 3)
    }
}
