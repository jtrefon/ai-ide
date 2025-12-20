import SwiftUI

fileprivate final class HostingContainer<Content: View>: NSView {
    let hostingView: NSHostingView<Content>

    init(rootView: Content) {
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rootView: Content) {
        hostingView.rootView = rootView
    }
}

struct AutosavingSplitView<Primary: View, Secondary: View>: NSViewRepresentable {
    enum Orientation {
        case horizontal
        case vertical
    }

    let autosaveName: NSSplitView.AutosaveName
    let orientation: Orientation
    let dividerStyle: NSSplitView.DividerStyle
    let primary: Primary
    let secondary: Secondary

    init(
        autosaveName: String,
        orientation: Orientation,
        dividerStyle: NSSplitView.DividerStyle = .thin,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.autosaveName = NSSplitView.AutosaveName(autosaveName)
        self.orientation = orientation
        self.dividerStyle = dividerStyle
        self.primary = primary()
        self.secondary = secondary()
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView(frame: .zero)
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = (orientation == .horizontal)
        splitView.dividerStyle = dividerStyle
        splitView.delegate = context.coordinator

        let primaryHost = HostingContainer(rootView: primary)
        let secondaryHost = HostingContainer(rootView: secondary)

        primaryHost.translatesAutoresizingMaskIntoConstraints = false
        primaryHost.identifier = NSUserInterfaceItemIdentifier(rawValue: "\(autosaveName).primary")
        
        secondaryHost.translatesAutoresizingMaskIntoConstraints = false
        secondaryHost.identifier = NSUserInterfaceItemIdentifier(rawValue: "\(autosaveName).secondary")
        
        splitView.addArrangedSubview(primaryHost)
        splitView.addArrangedSubview(secondaryHost)

        context.coordinator.primaryHost = primaryHost
        context.coordinator.secondaryHost = secondaryHost
        
        // Setting autosaveName after subviews are added and identifiers are set is more reliable
        splitView.autosaveName = autosaveName
        splitView.identifier = NSUserInterfaceItemIdentifier(rawValue: autosaveName)
        
        // Force immediate restoration of divider positions
        splitView.layoutSubtreeIfNeeded()

        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        nsView.isVertical = (orientation == .horizontal)
        nsView.dividerStyle = dividerStyle
        if nsView.autosaveName != autosaveName {
            nsView.autosaveName = autosaveName
        }

        context.coordinator.primaryHost?.update(rootView: primary)
        context.coordinator.secondaryHost?.update(rootView: secondary)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        fileprivate var primaryHost: HostingContainer<Primary>?
        fileprivate var secondaryHost: HostingContainer<Secondary>?
    }
}

typealias AutosavingHSplitView<Left: View, Right: View> = AutosavingSplitView<Left, Right>

typealias AutosavingVSplitView<Top: View, Bottom: View> = AutosavingSplitView<Top, Bottom>
