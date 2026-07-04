import SwiftUI

enum AppConstantsColor {
    static let surfaceBackground = Color(nsColor: .windowBackgroundColor)
    static let surfaceSidebar = Color(nsColor: .controlBackgroundColor)
    static let surfaceCard = Color(nsColor: .controlBackgroundColor)
    static let surfaceElevated = Color(nsColor: .windowBackgroundColor)

    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    static let accentDefault = Color.accentColor
    static let accentSubtle = Color.accentColor.opacity(0.12)

    static let terminalForeground = Color(nsColor: .textColor)
    static let terminalBackground = Color(nsColor: .textBackgroundColor)

    static let separatorSubtle = Color(nsColor: .separatorColor).opacity(0.25)
    static let separatorDefault = Color(nsColor: .separatorColor)
}
