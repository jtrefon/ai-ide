import Foundation

enum ToolFeedbackStatus: String, Sendable, Codable { case success, error, partial }

struct ToolFeedback: Sendable, Codable {
    let status: ToolFeedbackStatus
    let message: String
    let content: ToolContent?
    let error: ToolErrorInfo?

    static func success(_ m: String) -> ToolFeedback {
        ToolFeedback(status: .success, message: m, content: nil, error: nil)
    }
    static func success(_ m: String, text: String, meta: [String: String]? = nil) -> ToolFeedback {
        ToolFeedback(status: .success, message: m, content: ToolContent(data: .text(text), metadata: meta), error: nil)
    }
    static func success(_ m: String, items: [ToolContentItem], meta: [String: String]? = nil) -> ToolFeedback {
        ToolFeedback(status: .success, message: m, content: ToolContent(data: .items(items), metadata: meta), error: nil)
    }
    static func error(_ m: String, code: String, rec: Bool = true, alts: [ToolAlternative]? = nil) -> ToolFeedback {
        ToolFeedback(status: .error, message: m, content: nil,
                     error: ToolErrorInfo(code: code, message: m, recoverable: rec, alternatives: alts))
    }
    static func mustReadFirst(_ p: String) -> ToolFeedback {
        ToolFeedback.error("Read " + p + " first.", code: "MUTATION_WITHOUT_PRIOR_READ",
                          alts: [ToolAlternative(desc: "Read the file", tool: "read_file", args: ["path": p])])
    }
}

struct ToolContent: Sendable, Codable {
    let data: ToolContentData
    let metadata: [String: String]?
}

enum ToolContentData: Sendable, Codable {
    case text(String)
    case items([ToolContentItem])
    case empty
}

struct ToolContentItem: Sendable, Codable {
    let label: String
    let description: String?
    let path: String?
    let lineNumber: Int?
    let kind: String?
    init(l: String, d: String? = nil, p: String? = nil, ln: Int? = nil, k: String? = nil) {
        label = l; description = d; path = p; lineNumber = ln; kind = k
    }
}

struct ToolErrorInfo: Sendable, Codable {
    let code: String
    let message: String
    let recoverable: Bool
    let alternatives: [ToolAlternative]?
    init(code: String, message: String, recoverable: Bool, alternatives: [ToolAlternative]? = nil) {
        self.code = code; self.message = message; self.recoverable = recoverable; self.alternatives = alternatives
    }
}

struct ToolAlternative: Sendable, Codable {
    let description: String
    let suggestion: String?
    let toolName: String?
    let arguments: [String: String]?
    init(desc: String, sug: String? = nil, tool: String? = nil, args: [String: String]? = nil) {
        self.description = desc; self.suggestion = sug; self.toolName = tool; self.arguments = args
    }
}

/// Formats ToolFeedback into a string the model can read.
/// CRITICAL: must include content (file contents, search results) not just status.
struct ToolFeedbackFormatter {
    func format(_ fb: ToolFeedback) -> String {
        var lines: [String] = []
        lines.append("status: \(fb.status.rawValue)")
        lines.append("message: \(fb.message)")

        // Include tool content — this is what the model actually reads!
        if let c = fb.content {
            switch c.data {
            case .text(let t):
                lines.append("content:")
                // Split into lines for readability, limit to 500 lines
                let textLines = t.split(separator: "\n", maxSplits: 500, omittingEmptySubsequences: false)
                for line in textLines {
                    lines.append("  \(line)")
                }
                if let meta = c.metadata {
                    for (k, v) in meta { lines.append("  [\(k): \(v)]") }
                }
            case .items(let items):
                for item in items {
                    var itemLine = "  - \(item.label)"
                    if let k = item.kind { itemLine += " (\(k))" }
                    lines.append(itemLine)
                    if let d = item.description { lines.append("    \(d)") }
                    if let p = item.path { lines.append("    path: \(p)") }
                    if let l = item.lineNumber { lines.append("    line: \(l)") }
                }
            case .empty:
                break
            }
        }

        if let e = fb.error {
            lines.append("error_code: \(e.code)")
            lines.append("recoverable: \(e.recoverable)")
            if let alts = e.alternatives {
                for alt in alts {
                    lines.append("  try: \(alt.description)")
                    if let t = alt.toolName { lines.append("  tool: \(t)") }
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    func formatBatch(_ fbs: [ToolFeedback]) -> String {
        fbs.enumerated().map { i, fb in
            "result_\(i + 1):\n" + format(fb).split(separator: "\n").map { "  " + $0 }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
