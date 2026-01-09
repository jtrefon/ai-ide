import Foundation

struct AllowlistedRunCommandTool: AIToolProgressReporting {
    let name = "run_command"
    let description = "Execute a shell command in the terminal (allowlisted for verify phase)."

    var parameters: [String: Any] {
        base.parameters
    }

    private let base: any AIToolProgressReporting
    private let allowedPrefixes: [String]

    init(base: any AIToolProgressReporting, allowedPrefixes: [String]) {
        self.base = base
        self.allowedPrefixes = allowedPrefixes
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let command = try validatedCommand(arguments: arguments)
        var merged = arguments
        merged["command"] = command
        return try await base.execute(arguments: merged)
    }

    func execute(arguments: [String: Any], onProgress: @Sendable @escaping (String) -> Void) async throws -> String {
        let command = try validatedCommand(arguments: arguments)
        var merged = arguments
        merged["command"] = command
        return try await base.execute(arguments: merged, onProgress: onProgress)
    }

    private func validatedCommand(arguments: [String: Any]) throws -> String {
        guard let raw = arguments["command"] as? String else {
            throw AppError.aiServiceError("Missing 'command' argument for run_command")
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw AppError.aiServiceError("Invalid 'command' for run_command (empty)")
        }

        if isAllowed(command: trimmed) {
            return trimmed
        }

        let prefixPreview = allowedPrefixes.joined(separator: ", ")
        throw AppError.aiServiceError("Command is not allowlisted for verify. Allowed prefixes: \(prefixPreview)")
    }

    private func isAllowed(command: String) -> Bool {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowedPrefixes.contains(where: { normalized.hasPrefix($0) })
    }
}
