import XCTest
import SwiftUI
@testable import osx_ide

@MainActor
final class UICompositionRootTests: XCTestCase {
    func testValidate_ReturnsIssuesForMissingVisiblePanels() {
        let eventBus = EventBus()
        let uiService = UIService(errorManager: ErrorManager(), eventBus: eventBus)
        let ui = UIStateManager(uiService: uiService, eventBus: eventBus)
        ui.isSidebarVisible = true
        ui.isTerminalVisible = true
        ui.isAIChatVisible = true

        let registry = UIRegistry()
        let issues = UICompositionRoot.validate(registry: registry, ui: ui)

        XCTAssertFalse(issues.isEmpty)
    }

    func testValidate_ReturnsNoIssuesWhenRequiredPluginsExist() {
        let eventBus = EventBus()
        let uiService = UIService(errorManager: ErrorManager(), eventBus: eventBus)
        let ui = UIStateManager(uiService: uiService, eventBus: eventBus)

        let registry = UIRegistry()
        registry.register(point: .sidebarLeft, name: "Internal.FileExplorer", icon: "folder", view: EmptyView())
        registry.register(point: .panelBottom, name: AppConstants.UI.internalTerminalPanelName, icon: "terminal", view: EmptyView())
        registry.register(point: .panelBottom, name: "Internal.Logs", icon: "doc.text", view: EmptyView())
        registry.register(point: .panelBottom, name: "Internal.Problems", icon: "triangle", view: EmptyView())
        registry.register(point: .panelRight, name: "Internal.AIChat", icon: "sparkles", view: EmptyView())

        let issues = UICompositionRoot.validate(registry: registry, ui: ui)

        XCTAssertTrue(issues.isEmpty)
    }
}
