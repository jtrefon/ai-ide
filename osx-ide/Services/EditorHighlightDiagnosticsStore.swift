import Foundation
import Combine

@MainActor
final class EditorHighlightDiagnosticsStore: ObservableObject {
    static let shared = EditorHighlightDiagnosticsStore()

    @Published private(set) var diagnostics: String = ""

    nonisolated(unsafe) private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("EditorHighlightDiagnosticsUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let diagnosticsText = note.userInfo?["diagnostics"] as? String {
                Task { @MainActor in
                    self.diagnostics = diagnosticsText
                }
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
