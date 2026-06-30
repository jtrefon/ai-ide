import SwiftUI
import Combine
import Terminal

/// SwiftUI wrapper around SwiftTerm that starts in the project root reported
/// by ``ProjectRootRegistry``.  The directory is set at process spawn time
/// (no visible `cd` command is injected).
struct NativeTerminalView: View {
    @Binding var currentDirectory: URL?
    @ObservedObject private var projectRootRegistry: ProjectRootRegistry
    @ObservedObject var ui: UIStateManager
    private let eventBus: EventBusProtocol
    @State private var clearPublisher = PassthroughSubject<Void, Never>()

    private var projectRoot: URL? { projectRootRegistry.current }

    init(currentDirectory: Binding<URL?>, ui: UIStateManager, eventBus: EventBusProtocol) {
        self._currentDirectory = currentDirectory
        self.ui = ui
        self.eventBus = eventBus
        self.projectRootRegistry = .shared
    }

    var body: some View {
        SwiftTermView(
            currentDirectory: $currentDirectory,
            shellPath: "/bin/zsh",
            projectDirectory: projectRoot,
            font: .monospacedSystemFont(ofSize: ui.fontSize, weight: .regular),
            onClear: clearPublisher.eraseToAnyPublisher()
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.terminalTextView)
        .onAppear {
            _ = eventBus.subscribe(to: TerminalClearRequestedEvent.self) { _ in
                clearPublisher.send()
            }
        }
    }
}
