import Foundation
import AppKit

enum UILayoutNormalizer {
    private static let minWindowWidth: CGFloat = 900
    private static let minWindowHeight: CGFloat = 600

    static func normalizeWindowFrame(_ frame: NSRect, screenVisibleFrame: NSRect) -> NSRect {
        var normalized = frame

        normalized.size.width = min(max(normalized.size.width, minWindowWidth), screenVisibleFrame.width)
        normalized.size.height = min(max(normalized.size.height, minWindowHeight), screenVisibleFrame.height)

        if normalized.origin.x < screenVisibleFrame.minX {
            normalized.origin.x = screenVisibleFrame.minX
        }
        if normalized.maxX > screenVisibleFrame.maxX {
            normalized.origin.x = screenVisibleFrame.maxX - normalized.width
        }
        if normalized.origin.y < screenVisibleFrame.minY {
            normalized.origin.y = screenVisibleFrame.minY
        }
        if normalized.maxY > screenVisibleFrame.maxY {
            normalized.origin.y = screenVisibleFrame.maxY - normalized.height
        }

        return normalized
    }

    static func normalizeSidebarWidth(_ width: Double, windowWidth: CGFloat) -> Double {
        let maxByWindow = max(AppConstants.Layout.minSidebarWidth, Double(windowWidth * 0.35))
        return clamp(width, min: AppConstants.Layout.minSidebarWidth, max: min(AppConstants.Layout.maxSidebarWidth, maxByWindow))
    }

    static func normalizeChatPanelWidth(_ width: Double, windowWidth: CGFloat) -> Double {
        let maxByWindow = max(AppConstants.Layout.minChatPanelWidth, Double(windowWidth * 0.45))
        return clamp(width, min: AppConstants.Layout.minChatPanelWidth, max: min(AppConstants.Layout.maxChatPanelWidth, maxByWindow))
    }

    static func normalizeTerminalHeight(_ height: Double, windowHeight: CGFloat) -> Double {
        let maxByWindow = max(AppConstants.Layout.minTerminalHeight, Double(windowHeight * 0.55))
        return clamp(height, min: AppConstants.Layout.minTerminalHeight, max: min(AppConstants.Layout.maxTerminalHeight, maxByWindow))
    }

    static func rebalanceHorizontalPanels(
        sidebarWidth: Double,
        chatWidth: Double,
        isSidebarVisible: Bool,
        isChatVisible: Bool,
        windowWidth: CGFloat,
        minimumEditorWidth: Double
    ) -> (sidebar: Double, chat: Double) {
        var sidebar = isSidebarVisible ? sidebarWidth : 0
        var chat = isChatVisible ? chatWidth : 0

        let minimumRequired = sidebar + chat + minimumEditorWidth
        let available = Double(windowWidth)

        guard minimumRequired > available, (sidebar + chat) > 0 else {
            return (sidebar, chat)
        }

        let overflow = minimumRequired - available
        let totalPanels = sidebar + chat
        let sidebarShare = sidebar / totalPanels
        let chatShare = chat / totalPanels

        if isSidebarVisible {
            sidebar = max(AppConstants.Layout.minSidebarWidth, sidebar - (overflow * sidebarShare))
        }
        if isChatVisible {
            chat = max(AppConstants.Layout.minChatPanelWidth, chat - (overflow * chatShare))
        }

        return (sidebar, chat)
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        max(minValue, min(maxValue, value))
    }
}
