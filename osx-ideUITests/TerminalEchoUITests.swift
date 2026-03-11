import XCTest

@MainActor
final class TerminalEchoUITests: BaseUITestCase {
    func testTerminalAcceptsCommandInput() {
        let robot = launchApp()
        let terminal = robot.terminal()
        terminal.assertVisible()

        terminal.run("pwd")
        let value = terminal.terminalView.value as? String ?? ""
        XCTAssertFalse(value.isEmpty, "Terminal output should not be empty")
    }
}
