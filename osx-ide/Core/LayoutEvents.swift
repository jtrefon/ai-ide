//
//  LayoutEvents.swift
//  osx-ide
//
//  Created by Jack Trefon on 21/12/2025.
//

import Foundation

/// Event triggered when the sidebar visibility changes.
public struct SidebarVisibilityChangedEvent: Event {
    public let isVisible: Bool
    
    public init(isVisible: Bool) {
        self.isVisible = isVisible
    }
}

/// Event triggered when the sidebar width changes.
public struct SidebarWidthChangedEvent: Event {
    public let width: Double
    
    public init(width: Double) {
        self.width = width
    }
}

/// Event triggered when the terminal height changes.
public struct TerminalHeightChangedEvent: Event {
    public let height: Double
    
    public init(height: Double) {
        self.height = height
    }
}

/// Event triggered when the chat panel width changes.
public struct ChatPanelWidthChangedEvent: Event {
    public let width: Double
    
    public init(width: Double) {
        self.width = width
    }
}

public struct TerminalClearRequestedEvent: Event {
    public init() {}
}

public struct LogsFollowChangedEvent: Event {
    public let follow: Bool

    public init(follow: Bool) {
        self.follow = follow
    }
}

public struct LogsSourceChangedEvent: Event {
    public let sourceRawValue: String

    public init(sourceRawValue: String) {
        self.sourceRawValue = sourceRawValue
    }
}

public struct LogsClearRequestedEvent: Event {
    public init() {}
}

public struct ProblemsClearRequestedEvent: Event {
    public init() {}
}
