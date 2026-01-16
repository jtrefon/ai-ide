import AppKit

final class TerminalContentViewCoordinator {
    struct TerminalEmbedConfiguration {
        let directory: URL?
        let fontSize: Double
        let fontFamily: String
    }

    private var lastEmbeddedPath: String?
    private var lastFontSize: Double?
    private var lastFontFamily: String?

    func scheduleEmbed(
        into view: NSView,
        embedder: NativeTerminalEmbedder,
        configuration: TerminalEmbedConfiguration
    ) {
        let path = configuration.directory?.standardizedFileURL.path
        guard lastEmbeddedPath != path
                || lastFontSize != configuration.fontSize
                || lastFontFamily != configuration.fontFamily else { return }
        lastEmbeddedPath = path
        lastFontSize = configuration.fontSize
        lastFontFamily = configuration.fontFamily

        Task { @MainActor in
            await Task.yield()
            embedder.embedTerminal(
                in: view,
                directory: configuration.directory,
                fontSize: configuration.fontSize,
                fontFamily: configuration.fontFamily
            )
        }
    }
}
