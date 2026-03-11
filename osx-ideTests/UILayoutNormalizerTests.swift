import XCTest
import AppKit
@testable import osx_ide

final class UILayoutNormalizerTests: XCTestCase {
    func testNormalizeWindowFrame_ClampsToVisibleFrame() {
        let visible = NSRect(x: 100, y: 100, width: 1200, height: 800)
        let frame = NSRect(x: -300, y: -200, width: 2400, height: 1400)

        let normalized = UILayoutNormalizer.normalizeWindowFrame(frame, screenVisibleFrame: visible)

        XCTAssertGreaterThanOrEqual(normalized.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(normalized.minY, visible.minY)
        XCTAssertLessThanOrEqual(normalized.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(normalized.maxY, visible.maxY)
    }

    func testNormalizeSidebarWidth_UsesBounds() {
        let value = UILayoutNormalizer.normalizeSidebarWidth(999, windowWidth: 1000)
        XCTAssertLessThanOrEqual(value, 350)
        XCTAssertGreaterThanOrEqual(value, AppConstants.Layout.minSidebarWidth)
    }

    func testNormalizeChatWidth_UsesBounds() {
        let value = UILayoutNormalizer.normalizeChatPanelWidth(10, windowWidth: 900)
        XCTAssertGreaterThanOrEqual(value, AppConstants.Layout.minChatPanelWidth)
    }

    func testNormalizeTerminalHeight_UsesBounds() {
        let value = UILayoutNormalizer.normalizeTerminalHeight(1000, windowHeight: 700)
        XCTAssertLessThanOrEqual(value, 385.1)
        XCTAssertGreaterThanOrEqual(value, AppConstants.Layout.minTerminalHeight)
    }

    func testRebalanceHorizontalPanels_PreservesEditorMinimum() {
        let result = UILayoutNormalizer.rebalanceHorizontalPanels(
            sidebarWidth: 350,
            chatWidth: 450,
            isSidebarVisible: true,
            isChatVisible: true,
            windowWidth: 1000,
            minimumEditorWidth: 400
        )

        XCTAssertLessThanOrEqual(result.sidebar + result.chat + 400, 1000)
    }

    func testNormalizedMinWindowSize_AdaptsToSmallScreens() {
        let tinyVisible = NSRect(x: 0, y: 0, width: 640, height: 420)

        let size = UILayoutNormalizer.normalizedMinWindowSize(screenVisibleFrame: tinyVisible)

        XCTAssertEqual(size.width, 640, accuracy: 0.1)
        XCTAssertEqual(size.height, 420, accuracy: 0.1)
    }

    func testNormalizedDefaultWindowFrame_IsInsideVisibleFrame() {
        let visible = NSRect(x: 40, y: 30, width: 1200, height: 760)

        let frame = UILayoutNormalizer.normalizedDefaultWindowFrame(screenVisibleFrame: visible)

        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
    }
}
