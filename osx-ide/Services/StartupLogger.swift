//
//  StartupLogger.swift
//  osx-ide
//
//  Lightweight diagnostic logger for app startup. Disabled in release builds.
//

import Foundation

/// Writes startup diagnostics to a timestamped log file.
/// Automatically disabled when `#if DEBUG` is false.
enum StartupLogger {

    private static let queue = DispatchQueue(label: "osx-ide.startup-logger")

    #if DEBUG
    nonisolated(unsafe) private static var logURL: URL = {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("osx-ide-startup-\(ProcessInfo.processInfo.processIdentifier).log")
    }()

    nonisolated(unsafe) private static var isFirstWrite = true
    #endif

    /// Log a startup diagnostic message with an optional elapsed time.
    static func log(_ message: String, elapsedMs: Int? = nil) {
        #if DEBUG
        queue.async {
            let ts = ISO8601DateFormatter().string(from: Date())
            let elapsed = elapsedMs.map { " (\($0)ms)" } ?? ""
            let line = "[\(ts)] \(message)\(elapsed)\n"

            if isFirstWrite {
                isFirstWrite = false
                try? line.write(to: logURL, atomically: true, encoding: .utf8)
            } else {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: line.data(using: .utf8)!)
                    try? handle.close()
                }
            }

            Swift.print("[STARTUP] \(message)\(elapsed)")
            fflush(stdout)
        }
        #endif
    }
}
