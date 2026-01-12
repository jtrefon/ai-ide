import Foundation

/// Robust logger for indexing operations that writes to .ide/logs/indexing.log
public actor IndexLogger {
    public static let shared = IndexLogger()
    private var logFileURL: URL?
    private var setupRootPath: String?
    
    private init() {}
    
    /// Initializes the logger with the project root. Should be called as early as possible.
    public func setup(projectRoot: URL) {
        let rootPath = projectRoot.standardizedFileURL.path
        if let setupRootPath, setupRootPath == rootPath {
            // Already configured for this project root.
            return
        }

        let ideDir = projectRoot.appendingPathComponent(".ide", isDirectory: true)
        let logsDir = ideDir.appendingPathComponent("logs", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            let fileURL = logsDir.appendingPathComponent("indexing.log")
            self.logFileURL = fileURL
            self.setupRootPath = rootPath
            
            // Ensure the file exists so FileHandle can open it
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            
            internalLog("--- Indexing Logger Initialized ---")
            internalLog("Project Root: \(projectRoot.path)")
            internalLog("Log File: \(fileURL.path)")
        } catch {
            Task {
                await CrashReporter.shared.capture(
                    error,
                    context: CrashReportContext(operation: "IndexLogger.setup"),
                    metadata: ["projectRoot": projectRoot.path],
                    file: #fileID,
                    function: #function,
                    line: #line
                )
            }
            print("[IndexLogger] CRITICAL ERROR: Could not setup logs directory: \(error)")
        }
    }
    
    /// Public log method
    public func log(_ message: String) {
        internalLog(message)
    }
    
    private func internalLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        
        // Console output for immediate feedback
        print("[IndexLogger] \(message)")
        
        guard let url = logFileURL else { 
            // Fallback if setup hasn't been called yet
            return 
        }
        
        do {
            if let data = line.data(using: .utf8) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            }
        } catch {
            print("[IndexLogger] Error writing to log file: \(error)")
        }
    }
}
