import SwiftUI
import AppKit

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
    
    /// Subtle blur effect for backgrounds only
    var backgroundBlur: CGFloat {
        switch self {
        case .header, .toolbar:
            return 8
        case .sidebar:
            return 12
        case .panel, .popover:
            return 10
        case .sheet:
            return 15
        }
    }
}

extension View {
    /// Applies macOS v26 native liquid glass background with enhanced depth and clarity
    @ViewBuilder
    func nativeGlassBackground(_ surface: NativeGlassSurface) -> some View {
        self
            .background(surface.material)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .blur(radius: surface.backgroundBlur)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    /// Enhanced glass background with custom corner radius for different surfaces
    @ViewBuilder
    func nativeGlassBackground(_ surface: NativeGlassSurface, cornerRadius: CGFloat) -> some View {
        self
            .background(surface.material)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .blur(radius: surface.backgroundBlur)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    
    /// Creates a subtle glass card with minimal elevation effects
    @ViewBuilder
    func liquidGlassCard(elevation: Double = 0.3) -> some View {
        self
            .background(.ultraThinMaterial)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .blur(radius: 8 + elevation * 8)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
            )
    }
}
