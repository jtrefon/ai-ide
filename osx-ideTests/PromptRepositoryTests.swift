import XCTest
@testable import osx_ide

@MainActor
final class PromptRepositoryTests: XCTestCase {
    
    func testPromptRepositoryFallbackDisabled() async {
        // This should succeed since the file exists
        let content: String
        do {
            content = try PromptRepository.shared.fallbackPrompt(
                key: "ConversationFlow/Corrections/tool_loop_focused_execution",
                defaultValue: "default value",
                allowFallback: false,
                projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
            )
        } catch {
            XCTFail("Expected prompt load to succeed, got error: \(error)")
            return
        }
        
        // Should get the actual file content, not the default
        XCTAssertNotEqual(content, "default value")
        XCTAssertTrue(content.contains("focused execution mode"))
    }
    
    func testPromptRepositoryFallbackEnabled() async {
        // This should return the default value since file doesn't exist but fallback is enabled
        let content: String
        do {
            content = try PromptRepository.shared.fallbackPrompt(
                key: "NonExistent/file",
                defaultValue: "default value",
                allowFallback: true,
                projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
            )
        } catch {
            XCTFail("Expected fallback prompt load to succeed, got error: \(error)")
            return
        }
        
        XCTAssertEqual(content, "default value")
    }
    
    func testPromptRepositoryExistingFileWithFallbackEnabled() async {
        // This should still return the actual file content even with fallback enabled
        let content: String
        do {
            content = try PromptRepository.shared.fallbackPrompt(
                key: "ConversationFlow/Corrections/tool_loop_focused_execution",
                defaultValue: "default value",
                allowFallback: true,
                projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
            )
        } catch {
            XCTFail("Expected prompt load to succeed, got error: \(error)")
            return
        }
        
        XCTAssertNotEqual(content, "default value")
        XCTAssertTrue(content.contains("focused execution mode"))
    }
    
    func testPromptRepositoryPromptRemainsStrictWhenExplicitFallbackIsAllowed() async {
        XCTAssertThrowsError(
            try PromptRepository.shared.prompt(
                key: "NonExistent/file",
                projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
            )
        ) { error in
            guard case AppError.promptLoadingFailed = error else {
                XCTFail("Expected AppError.promptLoadingFailed, got: \(error)")
                return
            }
        }
    }
    
    func testPromptRepositoryEmptyFileWithFallbackEnabled() async {
        // Create a temporary empty file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("empty_prompt.md")
        
        try? "   ".write(to: tempFile, atomically: true, encoding: .utf8)
        
        // This should return the default value since file is empty but fallback is enabled
        let content: String
        do {
            content = try PromptRepository.shared.fallbackPrompt(
                key: "empty_prompt",
                defaultValue: "default value",
                allowFallback: true,
                projectRoot: tempDir
            )
        } catch {
            XCTFail("Expected fallback for empty prompt file, got error: \(error)")
            return
        }
        
        XCTAssertEqual(content, "default value")
        
        // Clean up
        try? FileManager.default.removeItem(at: tempFile)
    }

    func testPromptRepositoryMissingPromptThrowsWhenFallbackDisabled() async {
        XCTAssertThrowsError(
            try PromptRepository.shared.fallbackPrompt(
                key: "NonExistent/file",
                defaultValue: "default value",
                allowFallback: false,
                projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
            )
        ) { error in
            guard case AppError.promptLoadingFailed = error else {
                XCTFail("Expected AppError.promptLoadingFailed, got: \(error)")
                return
            }
        }
    }
}
