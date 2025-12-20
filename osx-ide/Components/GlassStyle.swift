import SwiftUI

/// Describes common app surfaces for applying native SwiftUI materials.
enum NativeGlassSurface {
    case header
    case sidebar
    case panel

    /// A SwiftUI-native background material appropriate for each surface.
    var material: some ShapeStyle {
        switch self {
        case .header:
            // Use the standard bar material for headers/toolbars.
            return .bar
        case .sidebar:
            // Use a very light/translucent material and layer it over a dark base to resemble Terminal's sidebar.
            return .ultraThinMaterial
        case .panel:
            // Regular material works well for general panels and content chrome.
            return .regularMaterial
        }
    }
}

extension View {
    /// Applies a native SwiftUI material background appropriate for the given surface,
    /// tuned to resemble the macOS Terminal look (dark, subtle translucency).
    @ViewBuilder
    func nativeGlassBackground(_ surface: NativeGlassSurface) -> some View {
        switch surface {
        case .header:
            // Headers/toolbars use the bar material directly for correct blending with the titlebar.
            self.background(surface.material)
        case .sidebar, .panel:
            // Layer a dark base color and overlay with the selected material for a Terminal-like effect.
            self
                .background(Color.black.opacity(0.65))
                .background(surface.material)
        }
    }
}
