import SwiftUI
import AppKit

struct NavigationLocationsOverlayView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(appState.navigationLocationsTitle)
                    .font(.headline)

                Spacer()

                Button("Close") {
                    close()
                }
            }

            List {
                ForEach(appState.navigationLocations) { loc in
                    Button(action: {
                        open(loc, openToSide: NSEvent.modifierFlags.contains(.command))
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(loc.relativePath):\(loc.line)")
                                .font(.system(.body, design: .monospaced))
                            if !loc.snippet.isEmpty {
                                Text(loc.snippet)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 820, minHeight: 460)
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 30)
        .onExitCommand {
            close()
        }
    }

    private func open(_ loc: WorkspaceCodeLocation, openToSide: Bool) {
        guard let root = appState.workspace.currentDirectory?.standardizedFileURL else { return }

        do {
            let url = try PathValidator(projectRoot: root).validateAndResolve(loc.relativePath)
            if openToSide {
                appState.fileEditor.openInOtherPane(from: url)
            } else {
                appState.loadFile(from: url)
            }
            appState.fileEditor.selectLine(loc.line)
            close()
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func close() {
        isPresented = false
        appState.navigationLocations = []
        appState.navigationLocationsTitle = ""
    }
}
