//
//  AppConstants.swift
//  osx-ide
//
//  Created by Jack Trefon on 20/12/2025.
//

import Foundation
import AppKit
import SwiftUI

/// Application constants to replace magic numbers
enum AppConstants {
    
    // MARK: - Terminal Constants
    
    enum Terminal {
        static let defaultRows = 24
        static let defaultColumns = 150 // Increased to prevent premature wrapping
        static let charWidth: CGFloat = 7.2
        static let charHeight: CGFloat = 14.0
        static let responseDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds
        static let terminalFontSize: CGFloat = 12
        static let terminalFontWeight: NSFont.Weight = .regular
    }
    
    // MARK: - Editor Constants
    
    enum Editor {
        static let defaultFontSize: Double = 12
        static let minFontSize: Double = 8
        static let maxFontSize: Double = 72
        static let lineNumberWidth: CGFloat = 45
        static let lineHeight: CGFloat = 15
        static let tabWidth: Int = 4
    }
    
    // MARK: - Layout Constants
    
    enum Layout {
        static let defaultSidebarWidth: Double = 250
        static let defaultTerminalHeight: Double = 200
        static let defaultChatPanelWidth: Double = 300
        static let minSidebarWidth: Double = 150
        static let maxSidebarWidth: Double = 500
        static let minTerminalHeight: Double = 100
        static let maxTerminalHeight: Double = 600
        static let minChatPanelWidth: Double = 200
        static let maxChatPanelWidth: Double = 600
        static let headerHeight: CGFloat = 30
    }
    
    // MARK: - File System Constants
    
    enum FileSystem {
        static let maxFileNameLength = 255
        static let maxPathLength = 4096
        static let maxRecentFiles = 10
        static let maxHistoryCount = 50
    }
    
    // MARK: - Time Constants
    
    enum Time {
        static let errorAutoDismissDelay: TimeInterval = 5.0
        static let searchDebounceDelay: TimeInterval = 0.25
        static let processTerminationTimeout: TimeInterval = 0.5
    }
    
    // MARK: - Color Constants
    
    enum Colors {
        static let terminalGreen = NSColor.green
        static let terminalBlack = NSColor.black
        static let terminalWhite = NSColor.white
        static let accentColor = Color.accentColor
        static let secondaryColor = Color.secondary
    }
    
    // MARK: - Validation Constants
    
    enum Validation {
        static let reservedFileNames = [
            "CON", "PRN", "AUX", "NUL", 
            "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
        ]
        static let invalidFileNameChars = CharacterSet(charactersIn: "<>:\"?*\\n\\r/\\\\")
    }
    
    // MARK: - AI Service Constants
    
    enum AI {
        static let defaultResponseDelay: UInt64 = 1_000_000_000
        static let minResponseDelay: UInt64 = 100_000_000 // 0.1 seconds
        static let maxResponseDelay: UInt64 = 10_000_000_000 // 10 seconds
    }
    
    // MARK: - Storage Constants
    
    enum Storage {
        static let themeKey = "AppTheme"
        static let fontSizeKey = "FontSize"
        static let fontFamilyKey = "FontFamily"
        static let lastWorkspacePathKey = "LastWorkspacePath"
        static let showLineNumbersKey = "ShowLineNumbers"
        static let wordWrapKey = "WordWrap"
        static let minimapVisibleKey = "MinimapVisible"
        static let sidebarWidthKey = "SidebarWidth"
        static let terminalHeightKey = "TerminalHeight"
        static let chatPanelWidthKey = "ChatPanelWidth"
    }
}