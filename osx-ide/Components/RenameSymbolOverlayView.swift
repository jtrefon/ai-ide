import SwiftUI
import Foundation

struct RenameSymbolOverlayView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var newName: String = ""
    @State private var previewReplacements: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Rename \"\(appState.renameSymbolIdentifier)\"")
                    .font(.headline)

                Spacer()

                Button("Close") {
                    close()
                }
            }

            TextField("New name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 520)
                .onSubmit {
                    applyRename()
                }

            HStack {
                Text("Replacements: \(previewReplacements)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Rename") {
                    applyRename()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 30)
        .onAppear {
            newName = appState.renameSymbolIdentifier
            previewReplacements = computePreviewReplacements()
        }
        .onChange(of: newName) { _, _ in
            previewReplacements = computePreviewReplacements()
        }
        .onExitCommand {
            close()
        }
    }

    private func computePreviewReplacements() -> Int {
        let old = appState.renameSymbolIdentifier
        if old.isEmpty { return 0 }
        if !WorkspaceNavigationService.isValidIdentifier(newName.trimmingCharacters(in: .whitespacesAndNewlines)) { return 0 }

        let content = appState.fileEditor.editorContent
        let escaped = NSRegularExpression.escapedPattern(for: old)
        let pattern = "\\b\(escaped)\\b"
        let regex = try? NSRegularExpression(pattern: pattern)
        let ns = content as NSString
        return regex?.numberOfMatches(in: content, range: NSRange(location: 0, length: ns.length)) ?? 0
    }

    private func applyRename() {
        do {
            let result = try WorkspaceNavigationService.renameInCurrentBuffer(
                content: appState.fileEditor.editorContent,
                identifier: appState.renameSymbolIdentifier,
                newName: newName
            )
            appState.fileEditor.editorContent = result.updated
            close()
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func close() {
        isPresented = false
        appState.renameSymbolIdentifier = ""
        newName = ""
        previewReplacements = 0
    }
}
