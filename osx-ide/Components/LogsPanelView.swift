import SwiftUI
import AppKit
import Combine

struct LogsPanelView: View {
    @ObservedObject var ui: UIStateManager
    let projectRoot: URL?
    private let eventBus: EventBusProtocol

    @State private var selectedSource: LogSource = .app
    @State private var follow: Bool = true
    @StateObject private var tailer: LogFileTailer
    @State private var followSubscription: AnyCancellable?
    @State private var sourceSubscription: AnyCancellable?
    @State private var clearSubscription: AnyCancellable?

    init(ui: UIStateManager, projectRoot: URL?, eventBus: EventBusProtocol) {
        self.ui = ui
        self.projectRoot = projectRoot
        self.eventBus = eventBus

        let fileURL = LogsPanelView.resolveURL(source: .app, projectRoot: projectRoot)
        _tailer = StateObject(wrappedValue: LogFileTailer(fileURL: fileURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(tailer.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: max(10, ui.fontSize - 2), design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(8)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: tailer.lines.count) { _, _ in
                    guard follow else { return }
                    if let last = tailer.lines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            tailer.start()

            followSubscription = eventBus.subscribe(to: LogsFollowChangedEvent.self) { event in
                follow = event.follow
            }
            sourceSubscription = eventBus.subscribe(to: LogsSourceChangedEvent.self) { event in
                if let src = LogSource(rawValue: event.sourceRawValue) {
                    selectedSource = src
                }
            }
            clearSubscription = eventBus.subscribe(to: LogsClearRequestedEvent.self) { _ in
                tailer.clear()
            }
        }
        .onDisappear {
            tailer.stop()
            followSubscription = nil
            sourceSubscription = nil
            clearSubscription = nil
        }
        .onChange(of: selectedSource) { _, newValue in
            tailer.setFileURL(LogsPanelView.resolveURL(source: newValue, projectRoot: projectRoot))
        }
    }

    private static func resolveURL(source: LogSource, projectRoot _: URL?) -> URL {
        switch source {
        case .app:
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
            return base
                .appendingPathComponent("osx-ide/Logs", isDirectory: true)
                .appendingPathComponent(String(day), isDirectory: true)
                .appendingPathComponent("app.ndjson")

        case .aiTrace:
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let logsDir = base.appendingPathComponent("osx-ide/Logs", isDirectory: true)
            if let url = mostRecentNDJSON(in: logsDir, namePrefix: "ai-trace-") {
                return url
            }
            return logsDir.appendingPathComponent("empty.ndjson")

        case .conversation:
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
            let dir = base
                .appendingPathComponent("osx-ide/Logs", isDirectory: true)
                .appendingPathComponent(String(day), isDirectory: true)
                .appendingPathComponent("conversations", isDirectory: true)

            if let url = mostRecentNDJSON(in: dir, namePrefix: nil) {
                return url
            }
            return dir.appendingPathComponent("empty.ndjson")

        case .projectIndex:
            return FileManager.default.temporaryDirectory.appendingPathComponent("missing.log")
        }
    }

    private static func mostRecentNDJSON(in directory: URL, namePrefix _: String?) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        let ndjson = items.filter {
            guard $0.pathExtension == "ndjson" else { return false }
            return true
        }
        return ndjson.max(by: { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        })
    }

    enum LogSource: String, CaseIterable, Identifiable {
        case app
        case aiTrace
        case projectIndex
        case conversation

        var id: String { rawValue }

        var title: String {
            switch self {
            case .app: return "App"
            case .aiTrace: return "AI Trace"
            case .projectIndex: return "Index"
            case .conversation: return "Conversation"
            }
        }
    }
}
