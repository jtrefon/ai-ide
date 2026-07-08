import Foundation

struct StallDetector {
    // MARK: - Repeated Batch
    private(set) var repeatedBatchCount = 0
    private var previousToolBatchSignature: String?

    mutating func detectRepeatedBatch(toolCalls: [AIToolCall], threshold: Int) -> Bool {
        let sig = toolBatchSignature(toolCalls)
        if sig == previousToolBatchSignature {
            repeatedBatchCount += 1
            return repeatedBatchCount >= threshold
        }
        previousToolBatchSignature = sig
        repeatedBatchCount = 0
        return false
    }

    // MARK: - Read-Only Loop
    private(set) var consecutiveReadOnlyIterations = 0
    private var previousReadOnlyBatchSignature: String?
    private(set) var repeatedReadOnlyBatchCount = 0

    mutating func detectReadOnlyLoop(toolCalls: [AIToolCall], threshold: Int, readOnlyNames: Set<String>) -> Bool {
        guard toolCalls.allSatisfy({ readOnlyNames.contains($0.name) }) else {
            consecutiveReadOnlyIterations = 0
            return false
        }
        consecutiveReadOnlyIterations += 1
        let sig = toolBatchSignature(toolCalls)
        if sig == previousReadOnlyBatchSignature {
            repeatedReadOnlyBatchCount += 1
        } else {
            repeatedReadOnlyBatchCount = 0
        }
        previousReadOnlyBatchSignature = sig
        return consecutiveReadOnlyIterations >= threshold
    }

    // MARK: - Repeated Signatures
    private(set) var repeatedCompletedSignatureCount = 0
    private var previousCompletedSignatures: Set<String>?

    mutating func detectRepeatedCompletedSignatures(current: Set<String>, threshold: Int) -> Bool {
        if current == previousCompletedSignatures {
            repeatedCompletedSignatureCount += 1
            return repeatedCompletedSignatureCount >= threshold
        }
        previousCompletedSignatures = current
        repeatedCompletedSignatureCount = 0
        return false
    }

    // MARK: - Empty Response
    private(set) var consecutiveEmptyResponses = 0

    mutating func detectEmptyResponse(hasContent: Bool, threshold: Int) -> Bool {
        if !hasContent {
            consecutiveEmptyResponses += 1
            return consecutiveEmptyResponses >= threshold
        }
        consecutiveEmptyResponses = 0
        return false
    }

    // MARK: - Repeated Write Target
    private(set) var repeatedWriteTargetCount = 0
    private var previousWriteTargetSignature: String?

    mutating func detectRepeatedWriteTarget(toolCalls: [AIToolCall], threshold: Int) -> String? {
        let sig = writeTargetSignature(toolCalls)
        guard let sig else { return nil }
        if sig == previousWriteTargetSignature {
            repeatedWriteTargetCount += 1
            if repeatedWriteTargetCount >= threshold { return sig }
        } else {
            repeatedWriteTargetCount = 0
        }
        previousWriteTargetSignature = sig
        return nil
    }

    mutating func reset() {
        repeatedBatchCount = 0
        previousToolBatchSignature = nil
        consecutiveReadOnlyIterations = 0
        previousReadOnlyBatchSignature = nil
        repeatedReadOnlyBatchCount = 0
        repeatedCompletedSignatureCount = 0
        previousCompletedSignatures = nil
        consecutiveEmptyResponses = 0
        repeatedWriteTargetCount = 0
        previousWriteTargetSignature = nil
    }

    // MARK: - Signatures

    static func toolCallSignature(_ call: AIToolCall) -> String {
        let sortedArgs = call.arguments.keys.sorted().map { "\($0)=\(call.arguments[$0] ?? "")" }.joined(separator: "&")
        return "\(call.name)|\(sortedArgs)"
    }

    private func toolBatchSignature(_ calls: [AIToolCall]) -> String {
        calls.map { Self.toolCallSignature($0) }.sorted().joined(separator: "::")
    }

    private func writeTargetSignature(_ calls: [AIToolCall]) -> String? {
        let paths = calls.compactMap { call -> String? in
            guard MutationTools.isMutationTool(call.name) else { return nil }
            return (call.arguments["path"] as? String) ?? (call.arguments["targetPath"] as? String)
        }
        guard !paths.isEmpty else { return nil }
        return paths.sorted().joined(separator: "|")
    }
}

enum MutationTools {
    static let mutationNames: Set<String> = ["write_file", "write_files", "create_file", "delete_file", "replace_in_file", "patch_file"]
    static let readOnlyNames: Set<String> = ["list_files", "read_file", "index_read_file", "index_find_files", "index_list_files", "index_list_symbols", "index_search_text", "index_search_symbols", "index_list_memories", "checkpoint_list", "conversation_fold"]
    static let contentWriteNames: Set<String> = ["read_file", "index_read_file", "create_file", "write_file", "write_files", "replace_in_file", "delete_file", "patch_file"]
    static let directReadNames: Set<String> = ["read_file", "index_read_file"]

    static func isMutationTool(_ name: String) -> Bool { mutationNames.contains(name) }
    static func isReadOnly(_ name: String) -> Bool { readOnlyNames.contains(name) }
    static func isDirectRead(_ name: String) -> Bool { directReadNames.contains(name) }
}
