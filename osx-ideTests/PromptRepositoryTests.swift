import XCTest
@testable import osx_ide

@MainActor
final class PromptRepositoryTests: XCTestCase {
    
    func testPromptRepositoryFallbackDisabled() async {
        // Test with fallback disabled (default)
        PromptRepository.allowFallback = false
        
        // This should succeed since the file exists
        let content = PromptRepository.shared.prompt(
            key: "ConversationFlow/Corrections/force_tool_followup",
            defaultValue: "default value",
            projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
        )
        
        // Should get the actual file content, not the default
        XCTAssertNotEqual(content, "default value")
        XCTAssertTrue(content.contains("implement changes"))
    }
    
    func testPromptRepositoryFallbackEnabled() async {
        // Test with fallback enabled
        PromptRepository.allowFallback = true
        
        // This should return the default value since file doesn't exist but fallback is enabled
        let content = PromptRepository.shared.prompt(
            key: "NonExistent/file",
            defaultValue: "default value",
            projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
        )
        
        XCTAssertEqual(content, "default value")
    }
    
    func testPromptRepositoryExistingFileWithFallbackEnabled() async {
        // Test with fallback enabled
        PromptRepository.allowFallback = true
        
        // This should still return the actual file content even with fallback enabled
        let content = PromptRepository.shared.prompt(
            key: "ConversationFlow/Corrections/force_tool_followup",
            defaultValue: "default value",
            projectRoot: URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")
        )
        
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
        let content = PromptRepository.shared.prompt(
            key: "empty_prompt",
            defaultValue: "default value",
            projectRoot: tempDir
        )
        
        XCTAssertEqual(content, "default value")
        
        // Clean up
        try? FileManager.default.removeItem(at: tempFile)
    }
}
