import XCTest
import Darwin
@testable import osx_ide

/// Reproduces the idle-timeout hang root cause offline: a provider that opens an
/// SSE stream, emits one event, then keeps the connection alive forever with
/// `: ping` keep-alives (never sends `[DONE]`) must now fail with
/// `OpenRouterServiceError.streamTimeout` instead of hanging `isSending` true.
final class SSEStreamTimeoutHarnessTests: XCTestCase {

    private func startSSEStallServer() throws -> (Process, Int) {
        let script = """
        import socket, threading, time, sys
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('127.0.0.1', 0))
        s.listen(1)
        sys.stdout.write(str(s.getsockname()[1]) + '\\n')
        sys.stdout.flush()
        def handle(conn):
            conn.recv(65536)
            conn.sendall(b'HTTP/1.1 200 OK\\r\\n')
            conn.sendall(b'Content-Type: text/event-stream\\r\\n')
            conn.sendall(b'Cache-Control: no-cache\\r\\n')
            conn.sendall(b'\\r\\n')
            conn.sendall(b'data: {"choices":[{"delta":{"content":"hi"}}]}\\n\\n')
            while True:
                time.sleep(1)
                try:
                    conn.sendall(b': ping\\n\\n')
                except Exception:
                    break
        threading.Thread(target=lambda: handle(s.accept()[0]), daemon=True).start()
        while True:
            time.sleep(1)
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sse_stall_server_\(UUID().uuidString).py")
        try script.write(to: url, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
        process.arguments = [url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()

        let data = pipe.fileHandleForReading.availableData
        let portStr = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let port = Int(portStr), !portStr.isEmpty else {
            process.terminate()
            throw XCTSkip("Could not read local SSE server port from stdout")
        }
        return (process, port)
    }

    func testStreamingStallRaisesStreamTimeout() async throws {
        let (server, port) = try startSSEStallServer()
        defer { server.terminate() }

        // Honour a short idle deadline so the test is fast and deterministic.
        setenv("OSXIDE_STREAM_IDLE_TIMEOUT_SEC", "2", 1)
        setenv("OSXIDE_STREAM_ABSOLUTE_TIMEOUT_SEC", "30", 1)

        let idle = SSEStreamDeadline.default().idle
        XCTAssertLessThan(idle, .seconds(10),
                          "env override for idle timeout must be honoured at runtime")

        let client = OpenRouterAPIClient(urlSession: URLSession.shared)
        let ctx = OpenRouterAPIClient.RequestContext(
            baseURL: "http://127.0.0.1:\(port)",
            appName: "",
            referer: ""
        )
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "x",
            "messages": [["role": "user", "content": "hi"]]
        ])

        try await Task.sleep(for: .milliseconds(200))

        let start = ContinuousClock.now
        var caught: Error?
        do {
            try await client.chatCompletionStreaming(apiKey: "", context: ctx, body: body) { _ in }
        } catch {
            caught = error
        }
        let elapsed = start.duration(to: .now)

        guard let error = caught else {
            XCTFail("Stalled SSE stream must raise a timeout, not hang (elapsed \(elapsed))")
            return
        }
        guard case OpenRouterServiceError.streamTimeout = error else {
            XCTFail("Expected streamTimeout, got \(error)")
            return
        }
        XCTAssertLessThan(elapsed, .seconds(20),
                          "Timeout should fire near the idle deadline, not hang")
    }
}
