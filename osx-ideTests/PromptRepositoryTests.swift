import XCTest
@testable import osx_ide

@MainActor
final class PromptRepositoryTests: XCTestCase {
    
    func testPromptRepositoryFallbackDisabled() async {
        // Test with fallback disabled (default)
        PromptRepository.allowFallback = false
        
        // This should succeed since the file exists
        let content: String
        do {
            content = try PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/force_tool_followup",
                defaultValue: "default value",
                projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
            )
        } catch {
            XCTFail("Expected prompt load to succeed, got error: \(error)")
            return
        }
        
        // Should get the actual file content, not the default
        XCTAssertNotEqual(content, "default value")
        XCTAssertTrue(content.contains("implement changes"))
    }
    
    func testPromptRepositoryFallbackEnabled() async {
        // Test with fallback enabled
        PromptRepository.allowFallback = true
        
        // This should return the default value since file doesn't exist but fallback is enabled
        let content: String
        do {
            content = try PromptRepository.shared.prompt(
                key: "NonExistent/file",
                defaultValue: "default value",
                projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
            )
        } catch {
            XCTFail("Expected fallback prompt load to succeed, got error: \(error)")
            return
        }
        
        XCTAssertEqual(content, "default value")
    }
    
    func testPromptRepositoryExistingFileWithFallbackEnabled() async {
        // Test with fallback enabled
        PromptRepository.allowFallback = true
        
        // This should still return the actual file content even with fallback enabled
        let content: String
        do {
            content = try PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/force_tool_followup",
                defaultValue: "default value",
                projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
            )
        } catch {
            XCTFail("Expected prompt load to succeed, got error: \(error)")
            return
        }
        
        XCTAssertNotEqual(content, "default value")
        XCTAssertTrue(content.contains("implement changes"))
    }
    
    func testPromptRepositoryFeatureFlagToggle() async {
        // Test that the feature flag can be toggled
        let originalValue = PromptRepository.allowFallback
        
        // Set to false
        PromptRepository.allowFallback = false
        XCTAssertEqual(PromptRepository.allowFallback, false)
        
        // Set to true
        PromptRepository.allowFallback = true
        XCTAssertEqual(PromptRepository.allowFallback, true)
        
        // Restore original value
        PromptRepository.allowFallback = originalValue
    }
    
    func testPromptRepositoryEmptyFileWithFallbackEnabled() async {
        // Test with fallback enabled
        PromptRepository.allowFallback = true
        
        // Create a temporary empty file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("empty_prompt.md")
        
        try? "   ".write(to: tempFile, atomically: true, encoding: .utf8)
        
        // This should return the default value since file is empty but fallback is enabled
        let content: String
        do {
            content = try PromptRepository.shared.prompt(
                key: "empty_prompt",
                defaultValue: "default value",
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
        PromptRepository.allowFallback = false

        XCTAssertThrowsError(
            try PromptRepository.shared.prompt(
                key: "NonExistent/file",
                defaultValue: "default value",
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
