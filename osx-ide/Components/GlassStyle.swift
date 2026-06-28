import SwiftUI

/// Modern macOS v26 liquid glass surface configurations
enum NativeGlassSurface {
    case header
    case sidebar
    case panel
    case toolbar
    case popover
    case sheet

    /// Enhanced material configuration for macOS v26 liquid glass effects
    var material: some ShapeStyle {
        switch self {
        case .header:
            // Subtle bar material with proper readability
            return .bar
        case .toolbar:
            return .thickMaterial
        case .sidebar:
            // Subtle material for sidebars maintaining readability
            return .thinMaterial
        case .panel:
            // Balanced material for content panels
            return .regularMaterial
        case .popover:
            // Elevated surface for popovers
            return .regularMaterial
        case .sheet:
            // Elevated surface for sheets
            return .thickMaterial
        }
    }

}

extension View {
    /// Applies macOS v26 native liquid glass background
    @ViewBuilder
    func nativeGlassBackground(_ surface: NativeGlassSurface) -> some View {
        self
            .background(surface.material)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Enhanced glass background with custom corner radius for different surfaces
    @ViewBuilder
    func nativeGlassBackground(_ surface: NativeGlassSurface, cornerRadius: CGFloat) -> some View {
        self
            .background(surface.material)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Creates a subtle glass card with minimal elevation effects
    @ViewBuilder
    func liquidGlassCard(elevation: Double = 0.3) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.separator.opacity(0.15), lineWidth: 0.5)
            )
    }
}
