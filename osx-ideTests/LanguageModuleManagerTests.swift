import Testing
@testable import osx_ide

@MainActor
struct LanguageModuleManagerTests {
    @Test func testHighlightModuleLookupRespectsCapabilityToggle() async throws {
        let manager = LanguageModuleManager.shared

        defer {
            manager.toggleCapability(.highlight, for: .typescript, enabled: true)
        }

        manager.toggleCapability(.highlight, for: .typescript, enabled: false)

        #expect(manager.getHighlightModule(for: .typescript) == nil)
        #expect(manager.getHighlightModule(forExtension: "ts") == nil)
    }

    @Test func testHighlightModuleLookupRestoresAfterReEnablingCapability() async throws {
        let manager = LanguageModuleManager.shared

        manager.toggleCapability(.highlight, for: .swift, enabled: false)
        manager.toggleCapability(.highlight, for: .swift, enabled: true)

        #expect(manager.getHighlightModule(for: .swift) != nil)
        #expect(manager.getHighlightModule(forExtension: "swift") != nil)
    }

    @Test func testUnsupportedCapabilityAlwaysDisabled() async throws {
        let manager = LanguageModuleManager.shared

        #expect(manager.isCapabilityEnabled(.lint, for: .javascript) == false)
        manager.toggleCapability(.lint, for: .javascript, enabled: true)
        #expect(manager.isCapabilityEnabled(.lint, for: .javascript) == false)
    }
}
