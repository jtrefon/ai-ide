import SwiftUI
import AppKit

struct ProblemsView<Context: IDEContext>: View {
    @ObservedObject var store: DiagnosticsStore
    let context: Context

    var body: some View {
        VStack(spacing: 0) {
            header
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
        }
    }

    private var header: some View {
        HStack {
            Text("Problems")
                .font(.system(size: max(10, context.ui.fontSize - 2), weight: .medium))

            Spacer()

            Button("Clear") {
                store.clear()
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 30)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @MainActor
    private func open(_ d: Diagnostic) {
        let root = context.workspace.currentDirectory?.standardizedFileURL
        let url: URL

        if d.relativePath.hasPrefix("/") {
            url = URL(fileURLWithPath: d.relativePath)
        } else if let root {
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
