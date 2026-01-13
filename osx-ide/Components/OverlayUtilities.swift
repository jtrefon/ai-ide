import Foundation

enum OverlayLocalizer {
    static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

enum OverlaySearchDebouncer {
    static func reschedule(
        searchTask: inout Task<Void, Never>?,
        debounceNanoseconds: UInt64,
        action: @MainActor @escaping () async -> Void
    ) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            await action()
        }
    }
}
