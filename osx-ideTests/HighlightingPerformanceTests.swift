//
//  HighlightingPerformanceTests.swift
//  osx-ide
//
//  Created by AI Assistant on 11/01/2026.
//

import XCTest
@testable import osx_ide

@MainActor
final class HighlightingPerformanceTests: XCTestCase {

    func testHighlightingPerformanceSmallFile() {
        let syntaxHighlighter = SyntaxHighlighter.shared
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let smallCode = """
        func helloWorld() {
            print("Hello, World!")
            let name = "Swift"
            print("Hello, \\(name)!")
        }
        """
        
        measure {
            _ = syntaxHighlighter.highlight(smallCode, language: "swift", font: font)
        }
    }

    func testHighlightingPerformanceMediumFile() {
        let syntaxHighlighter = SyntaxHighlighter.shared
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let mediumCode = String(repeating: """
        func calculateSum(_ numbers: [Int]) -> Int {
            return numbers.reduce(0, +)
        }

        func fibonacci(_ n: Int) -> Int {
            if n <= 1 { return n }
            return fibonacci(n - 1) + fibonacci(n - 2)
        }

        class Calculator {
            private var history: [String] = []

            func add(_ a: Double, _ b: Double) -> Double {
                let result = a + b
                history.add("\\(a) + \\(b) = \\(result)")
                return result
            }

            func multiply(_ a: Double, _ b: Double) -> Double {
                let result = a * b
                history.add("\\(a) * \\(b) = \\(result)")
                return result
            }
        }

        """, count: 10)

        measure {
            _ = syntaxHighlighter.highlight(mediumCode, language: "swift", font: font)
        }
    }

    func testHighlightingPerformanceLargeFile() {
        let syntaxHighlighter = SyntaxHighlighter.shared
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let largeCode = String(repeating: """
        import Foundation
        import UIKit

        class DataProcessor {
            private let queue = DispatchQueue(label: "com.example.processor", qos: .userInitiated)
            private var cache: [String: Any] = [:]

            func process(data: [String]) async -> [String] {
                return await withTaskGroup(of: String.self) { group in
                    for item in data {
                        group.addTask {
                            await processItem(item)
                        }
                    }

                    var results: [String] = []
                    for await result in group {
                        results.append(result)
                    }
                    return results
                }
            }

            private func processItem(_ item: String) async -> String {
                // Simulate processing
                try? await Task.sleep(nanoseconds: 1_000_000)
                return item.uppercased()
            }
        }

        """, count: 50)

        measure {
            _ = syntaxHighlighter.highlight(largeCode, language: "swift", font: font)
        }
    }

    func testIncrementalHighlightingPerformance() async {
        let syntaxHighlighter = SyntaxHighlighter.shared
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let originalCode = """
        func hello() {
            print("Hello")
        }
        """

        let modifiedCode = """
        func hello() {
            print("Hello, World!")
            let name = "Swift"
        }
        """

        let originalRequest = SyntaxHighlighter.HighlightIncrementalRequest(
            code: originalCode,
            language: "swift",
            font: font,
            previousResult: nil
        )
        let original = await syntaxHighlighter.highlightIncremental(originalRequest)

        let modifiedRequest = SyntaxHighlighter.HighlightIncrementalRequest(
            code: modifiedCode,
            language: "swift",
            font: font,
            previousResult: original
        )
        measure {
            Task {
                _ = await syntaxHighlighter.highlightIncremental(modifiedRequest)
            }
        }
    }
}
