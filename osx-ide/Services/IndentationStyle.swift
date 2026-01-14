import Foundation

// Canonical IndentationStyle is defined in Services/AppConstants.swift.
// This file is kept to avoid breaking any project file references; do not use this type.
enum IndentationStyleLegacy: String, CaseIterable, Codable, Sendable {
    case tabs
    case spaces
}
