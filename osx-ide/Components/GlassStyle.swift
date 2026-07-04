import SwiftUI

enum NativeGlassSurface {
    case header
    case sidebar
    case panel
    case toolbar
    case popover
    case sheet

    var material: some ShapeStyle {
        switch self {
        case .header:      return .bar
        case .toolbar:     return .thickMaterial
        case .sidebar:     return .thinMaterial
        case .panel:       return .regularMaterial
        case .popover:     return .regularMaterial
        case .sheet:       return .thickMaterial
        }
    }

    var defaultCornerRadius: CGFloat {
        switch self {
        case .header:  return AppConstants.Layout.cornerSm
        case .sidebar: return 0
        case .panel:   return AppConstants.Layout.cornerLg
        case .toolbar: return AppConstants.Layout.cornerSm
        case .popover: return AppConstants.Layout.cornerMd
        case .sheet:   return AppConstants.Layout.cornerLg
        }
    }
}

extension View {
    @ViewBuilder
    func nativeGlassBackground(_ surface: NativeGlassSurface, cornerRadius: CGFloat? = nil, showBorder: Bool = false) -> some View {
        let radius = cornerRadius ?? surface.defaultCornerRadius
        self
            .background(surface.material)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                showBorder
                    ? RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(AppConstants.Color.separatorSubtle, lineWidth: 0.5)
                    : nil
            )
    }
}
