import SwiftUI
import AppKit
import Combine

struct ProblemsView<Context: IDEContext>: View {
    @ObservedObject var store: DiagnosticsStore
    let context: Context
    @State private var clearSubscription: AnyCancellable?

    var body: some View {
        List {
            ForEach(store.diagnostics) { d in
                Button {
                    open(d)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: d.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                            .foregroundColor(d.severity == .error ? .red : .yellow)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.message)
                                .lineLimit(2)
                            Text(locationText(d))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            clearSubscription = context.eventBus.subscribe(to: ProblemsClearRequestedEvent.self) { _ in
                store.clear()
            }
        }
        .onDisappear {
            clearSubscription = nil
        }
    }

    @MainActor
    private func open(_ d: Diagnostic) {
        let url: URL

        if d.relativePath.hasPrefix("/") {
            url = URL(fileURLWithPath: d.relativePath)
        } else if let root = context.workspace.currentDirectory?.standardizedFileURL {
            do {
                url = try context.workspaceService.makePathValidator(projectRoot: root).validateAndResolve(d.relativePath)
            } catch {
                context.lastError = error.localizedDescription
                return
            }
        } else {
            context.lastError = "No workspace open."
            return
        }

        context.loadFile(from: url)
        context.fileEditor.selectLine(d.line)
    }

    private func locationText(_ d: Diagnostic) -> String {
        if let column = d.column {
            return "\(d.relativePath):\(d.line):\(column)"
        }
        return "\(d.relativePath):\(d.line)"
    }
}
