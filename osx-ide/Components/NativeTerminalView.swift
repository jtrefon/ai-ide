import SwiftUI
import Combine
import Terminal

struct NativeTerminalView: View {
    @Binding var currentDirectory: URL?
    let projectRoot: URL?
    @ObservedObject var ui: UIStateManager
    private let eventBus: EventBusProtocol
    @State private var clearPublisher = PassthroughSubject<Void, Never>()

    init(currentDirectory: Binding<URL?>, projectRoot: URL? = nil, ui: UIStateManager, eventBus: EventBusProtocol) {
        self._currentDirectory = currentDirectory
        self.projectRoot = projectRoot
        self.ui = ui
        self.eventBus = eventBus
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
        .onAppear {
            eventBus.subscribe(to: TerminalClearRequestedEvent.self) { _ in
                clearPublisher.send()
            }
        }
    }
}
