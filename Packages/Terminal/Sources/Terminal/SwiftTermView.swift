import SwiftUI
import AppKit
import SwiftTerm
import Combine

public struct SwiftTermView: NSViewRepresentable {
    @Binding var currentDirectory: URL?
    private let shellPath: String
    private let shellArgs: [String]
    private let projectDirectory: String?
    private let font: NSFont
    private let onClear: AnyPublisher<Void, Never>

    public init(
        currentDirectory: Binding<URL?>,
        shellPath: String = "/bin/bash",
        shellArgs: [String] = ["-l"],
        projectDirectory: URL? = nil,
        font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular),
        onClear: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()
    ) {
        self._currentDirectory = currentDirectory
        self.shellPath = shellPath
        self.shellArgs = shellArgs
        self.projectDirectory = projectDirectory?.standardizedFileURL.path
        self.font = font
        self.onClear = onClear
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let term = DragEnabledTerminalView(frame: .zero)
        term.font = font
        term.processDelegate = context.coordinator

        term.startProcess(
            executable: shellPath,
            args: shellArgs,
            currentDirectory: projectDirectory
        )

        context.coordinator.term = term
        context.coordinator.subscribeToClear()

        return term
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        nsView.font = font
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            currentDirectory: $currentDirectory,
            onClear: onClear
        )
    }

    public class Coordinator: LocalProcessTerminalViewDelegate {
        @Binding var currentDirectory: URL?
        let onClear: AnyPublisher<Void, Never>
        var term: LocalProcessTerminalView?
        private var cancellables = Set<AnyCancellable>()

        init(currentDirectory: Binding<URL?>, onClear: AnyPublisher<Void, Never>) {
            self._currentDirectory = currentDirectory
            self.onClear = onClear
        }

        func subscribeToClear() {
            onClear
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    self?.term?.getTerminal().resetToInitialState()
                }
                .store(in: &cancellables)
        }

        public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            if let dir = directory {
                currentDirectory = URL(fileURLWithPath: dir)
            }
        }

        public func processTerminated(source: TerminalView, exitCode: Int32?) {
            print("[Terminal] Process terminated with code: \(exitCode ?? -1)")
        }
    }
}
