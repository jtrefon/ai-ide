import XCTest

@MainActor
class BaseUITestCase: XCTestCase {
    private(set) var app: XCUIApplication!
    private var testProfilePath: String = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        testProfilePath = NSTemporaryDirectory() + "osx_ide_ui_profile_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: testProfilePath, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        if !testProfilePath.isEmpty {
            try? FileManager.default.removeItem(atPath: testProfilePath)
        }
    }

    @discardableResult
    func launchApp(scenario: String? = nil) -> AppRobot {
        app.launchEnvironment[TestLaunchKeys.xcuiTesting] = "1"
        app.launchEnvironment[TestLaunchKeys.testProfileDir] = testProfilePath
        app.launchEnvironment[TestLaunchKeys.disableHeavyInit] = "1"
        if let scenario {
            app.launchEnvironment[TestLaunchKeys.uiTestScenario] = scenario
        }

        app.launch()
        let robot = AppRobot(app: app)
        robot.waitForReady()
        return robot
    }
}

enum TestLaunchKeys {
    static let xcuiTesting = "XCUI_TESTING"
    static let testProfileDir = "OSXIDE_TEST_PROFILE_DIR"
    static let disableHeavyInit = "OSXIDE_DISABLE_HEAVY_INIT"
    static let uiTestScenario = "OSXIDE_TEST_SCENARIO"
}

enum UITestAccessibilityID {
    static let appRootView = "AppRootView"
    static let appReadyMarker = "AppReadyMarker"

    static let codeEditorTextView = "CodeEditorTextView"
    static let editorHighlightDiagnostics = "EditorHighlightDiagnostics"

    static let aiChatPanel = "AIChatPanel"
    static let aiChatInputTextView = "AIChatInputTextView"
    static let aiChatSendButton = "AIChatSendButton"
    static let aiChatNewConversationButton = "AIChatNewConversationButton"

    static let terminalTextView = "TerminalTextView"
    static let fileExplorerOutline = "FileExplorerOutline"
    static let statusBar = "StatusBar"
    static let leftSidebarPanel = "LeftSidebarPanel"
    static let rightChatPanel = "RightChatPanel"
    static let sidebarResizeHandle = "SidebarResizeHandle"
    static let chatResizeHandle = "ChatResizeHandle"
}

@MainActor
struct AppRobot {
    let app: XCUIApplication

    func waitForReady(timeout: TimeInterval = 30) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout), "App must reach foreground")
        app.activate()

        let readyMarker = app.staticTexts[UITestAccessibilityID.appReadyMarker]
        if readyMarker.waitForExistence(timeout: min(10, timeout)) {
            let readyDeadline = Date().addingTimeInterval(timeout)
            while Date() < readyDeadline {
                if (readyMarker.value as? String) == "ready" {
                    return
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            XCTFail("AppReadyMarker did not reach ready state in time. value=\(String(describing: readyMarker.value))")
            return
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (readyMarker.exists && ((readyMarker.value as? String) == "ready")) ||
                app.windows.firstMatch.exists ||
                app.textViews[UITestAccessibilityID.codeEditorTextView].exists ||
                app.descendants(matching: .any)[UITestAccessibilityID.terminalTextView].exists ||
                app.outlines[UITestAccessibilityID.fileExplorerOutline].exists ||
                app.buttons[UITestAccessibilityID.aiChatSendButton].exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail(
            "UI did not become ready in time. Missing core controls after window launch.\n\(app.debugDescription)"
        )
    }

    func editor() -> EditorRobot { EditorRobot(app: app) }
    func terminal() -> TerminalRobot { TerminalRobot(app: app) }
    func chat() -> ChatRobot { ChatRobot(app: app) }
    func settings() -> SettingsRobot { SettingsRobot(app: app) }
    func window() -> WindowRobot { WindowRobot(app: app) }
    func fileTree() -> FileTreeRobot { FileTreeRobot(app: app) }
}

@MainActor
struct EditorRobot {
    let app: XCUIApplication

    var editorView: XCUIElement { app.textViews[UITestAccessibilityID.codeEditorTextView] }

    func assertVisible() {
        XCTAssertTrue(editorView.waitForExistence(timeout: 10), "Editor must exist")
        XCTAssertTrue(editorView.isHittable, "Editor must be hittable")
    }

    func type(_ text: String) {
        editorView.click()
        editorView.typeText(text)
    }
}

@MainActor
struct TerminalRobot {
    let app: XCUIApplication

    var terminalView: XCUIElement {
        let byTextView = app.textViews[UITestAccessibilityID.terminalTextView]
        if byTextView.exists { return byTextView }
        return app.descendants(matching: .any)[UITestAccessibilityID.terminalTextView]
    }

    func assertVisible() {
        XCTAssertTrue(terminalView.waitForExistence(timeout: 10), "Terminal must exist")
    }

    func run(_ command: String) {
        terminalView.click()
        terminalView.typeText(command)
        terminalView.typeText("\n")
    }
}

@MainActor
struct ChatRobot {
    let app: XCUIApplication

    var panel: XCUIElement { app.otherElements[UITestAccessibilityID.aiChatPanel] }
    var input: XCUIElement {
        let byTextView = app.textViews[UITestAccessibilityID.aiChatInputTextView]
        if byTextView.exists { return byTextView }
        return app.descendants(matching: .any)[UITestAccessibilityID.aiChatInputTextView]
    }
    var send: XCUIElement { app.buttons[UITestAccessibilityID.aiChatSendButton] }
    var newConversation: XCUIElement { app.buttons[UITestAccessibilityID.aiChatNewConversationButton] }

    func assertVisible() {
        let sendExists = send.waitForExistence(timeout: 10)
        let newConversationExists = newConversation.waitForExistence(timeout: 10)
        let inputExists = input.waitForExistence(timeout: 10)

        XCTAssertTrue(sendExists, "Chat send button must exist")
        XCTAssertTrue(newConversationExists, "New conversation button must exist")
        XCTAssertTrue(
            inputExists,
            "Chat input must exist. panel=\(panel.exists) send=\(sendExists) newConversation=\(newConversationExists)\n\(app.debugDescription)"
        )
    }

    func sendMessage(_ text: String) {
        input.click()
        input.typeText(text)
        XCTAssertTrue(send.isEnabled, "Send button must be enabled")
        send.click()
    }
}

@MainActor
struct SettingsRobot {
    let app: XCUIApplication

    func openSettings() {
        app.typeKey(",", modifierFlags: [.command])
        if app.windows.count < 2 {
            let appMenu = app.menuBars.menuBarItems["osx-ide"]
            if appMenu.exists {
                appMenu.click()
                if app.menuItems["Settings…"].exists {
                    app.menuItems["Settings…"].click()
                } else if app.menuItems["Settings..."].exists {
                    app.menuItems["Settings..."].click()
                }
            }
        }
    }

    func assertWordWrapToggleVisible() {
        let toggle = app.switches["Settings.WordWrap"]
        if toggle.waitForExistence(timeout: 3) {
            return
        }

        let checkbox = app.checkBoxes["Settings.WordWrap"]
        if checkbox.waitForExistence(timeout: 3) {
            return
        }

        let any = app.descendants(matching: .any)["Settings.WordWrap"]
        XCTAssertTrue(any.waitForExistence(timeout: 4), "Word wrap toggle must exist")
    }
}

@MainActor
struct WindowRobot {
    let app: XCUIApplication

    var mainWindow: XCUIElement { app.windows.firstMatch }

    func assertVisible() {
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10), "Main window must exist")
    }

    func assertWithinMainDisplayBounds() {
        assertVisible()
        let frame = mainWindow.frame
        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        XCTAssertLessThanOrEqual(frame.width, displayBounds.width)
        XCTAssertLessThanOrEqual(frame.height, displayBounds.height)
        XCTAssertGreaterThanOrEqual(frame.minX, displayBounds.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, displayBounds.minY)
    }
}

@MainActor
struct FileTreeRobot {
    let app: XCUIApplication

    var outline: XCUIElement { app.outlines[UITestAccessibilityID.fileExplorerOutline] }

    func assertVisible() {
        XCTAssertTrue(outline.waitForExistence(timeout: 10), "File tree outline must exist")
    }
}

@MainActor
final class OSXIDEUITests: BaseUITestCase {
    func testAppLaunchesAndBecomesReady() {
        let robot = launchApp()
        robot.window().assertVisible()
    }
}
