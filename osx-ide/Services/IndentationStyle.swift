import Foundation

// Canonical IndentationStyle is defined in Services/AppConstants.swift.
// This file is kept to avoid breaking any project file references; do not use this type.
enum IndentationStyle: String, CaseIterable, Codable, Sendable {
    case tabs
    case spaces

    var displayName: String {
        switch self {
        case .tabs:
            return "Tabs"
        case .spaces:
            return "Spaces"
        }
    }

    static func current(userDefaults: UserDefaults = AppRuntimeEnvironment.userDefaults) -> IndentationStyle {
        if let raw = userDefaults.string(forKey: AppConstants.Storage.indentationStyleKey),
           let style = IndentationStyle(rawValue: raw) {
            return style
        }
        return .tabs
    }

    static func setCurrent(_ style: IndentationStyle, userDefaults: UserDefaults = AppRuntimeEnvironment.userDefaults) {
        userDefaults.set(style.rawValue, forKey: AppConstants.Storage.indentationStyleKey)
    }

    func indentUnit(tabWidth: Int = AppConstants.Editor.tabWidth) -> String {
        switch self {
        case .tabs:
            return "\t"
        case .spaces:
            return String(repeating: " ", count: tabWidth)
        }
    }
}
