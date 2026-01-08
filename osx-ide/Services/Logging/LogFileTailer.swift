import Foundation
import Combine

@MainActor
final class LogFileTailer: ObservableObject {
    @Published private(set) var lines: [String] = []

    private var timer: Timer?
    private var fileHandle: FileHandle?
    private var lastOffset: UInt64 = 0

    private var isRunning: Bool = false

    private var fileURL: URL
    private let maxLines: Int

    init(fileURL: URL, maxLines: Int = 2_000) {
        self.fileURL = fileURL
        self.maxLines = maxLines
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }

    func start() {
        stop()
        loadInitial()

        isRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readIncremental()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        try? fileHandle?.close()
        fileHandle = nil

        isRunning = false
    }

    func clear() {
        lines = []
    }

    func setFileURL(_ url: URL) {
        let wasRunning = isRunning
        stop()
        fileURL = url
        clear()
        lastOffset = 0
        if wasRunning {
            start()
        }
    }

    private func loadInitial() {
        guard let data = try? Data(contentsOf: fileURL) else {
            lines = []
            lastOffset = 0
            return
        }

        lastOffset = UInt64(data.count)
        let content = String(data: data, encoding: .utf8) ?? ""
        let split = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        lines = Array(split.suffix(maxLines))
    }

    private func readIncremental() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        if fileHandle == nil {
            fileHandle = try? FileHandle(forReadingFrom: fileURL)
            if let fileHandle {
                try? fileHandle.seek(toOffset: lastOffset)
            }
        }

        guard let fileHandle else { return }
        guard let data = try? fileHandle.readToEnd() else { return }
        guard !data.isEmpty else { return }

        lastOffset += UInt64(data.count)

        let appended = String(data: data, encoding: .utf8) ?? ""
        let newLines = appended.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !newLines.isEmpty else { return }

        var out = lines
        out.append(contentsOf: newLines)
        if out.count > maxLines {
            out.removeFirst(out.count - maxLines)
        }
        lines = out
    }
}
