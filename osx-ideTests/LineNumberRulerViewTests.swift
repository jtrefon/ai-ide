import Testing
import Foundation
import AppKit
@testable import osx_ide

@MainActor
struct LineNumberRulerViewTests {

    @Test func testStartingLineNumberCountsLinesUpToFirstCharIndex() async throws {
        let sampleString = "a\nb\nc\n" as NSString

        #expect(ModernLineNumberRulerView.startingLineNumber(string: sampleString, firstCharIndex: 0) == 1)
        #expect(ModernLineNumberRulerView.startingLineNumber(string: sampleString, firstCharIndex: 1) == 1)
        #expect(ModernLineNumberRulerView.startingLineNumber(string: sampleString, firstCharIndex: 2) == 2)
        #expect(ModernLineNumberRulerView.startingLineNumber(string: sampleString, firstCharIndex: 4) == 3)
    }
}
