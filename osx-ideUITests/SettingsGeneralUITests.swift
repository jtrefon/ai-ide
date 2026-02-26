import XCTest

@MainActor
final class SettingsGeneralUITests: BaseUITestCase {
    func testSettingsWindowOpensAndCoreControlIsVisible() {
        let robot = launchApp()
        robot.settings().openSettings()
        robot.settings().assertWordWrapToggleVisible()
    }
}
