import Foundation

struct ArtifactTracker {
    private(set) var mutatedArtifactPaths: Set<String> = []
    private(set) var previouslyFailedSignatures: Set<String> = []
    private(set) var previouslyCompletedSignatures: Set<String> = []
    private(set) var hasObservedSuccessfulMutation = false
    private(set) var hasObservedSuccessfulDirectRead = false
    private(set) var hasObservedMutationVerificationRead = false
    private(set) var consecutivePostMutationNonMutationIterations = 0
    private(set) var consecutiveNonRecoverableMutationFailureIterations = 0
    private(set) var lastContinuationRecoveryIteration = 0

    mutating func recordMutation(path: String) {
        mutatedArtifactPaths.insert(path)
        hasObservedSuccessfulMutation = true
        consecutivePostMutationNonMutationIterations = 0
    }

    mutating func recordDirectRead() {
        hasObservedSuccessfulDirectRead = true
    }

    mutating func recordVerificationRead() {
        hasObservedMutationVerificationRead = true
    }

    mutating func recordFailedSignature(_ sig: String) {
        previouslyFailedSignatures.insert(sig)
    }

    mutating func recordCompletedSignature(_ sig: String) {
        previouslyCompletedSignatures.insert(sig)
    }

    mutating func recordNonMutationIteration() {
        consecutivePostMutationNonMutationIterations += 1
    }

    mutating func recordNonRecoverableFailureIteration() {
        consecutiveNonRecoverableMutationFailureIterations += 1
    }

    mutating func resetNonMutationCount() {
        consecutivePostMutationNonMutationIterations = 0
    }

    mutating func resetNonRecoverableCount() {
        consecutiveNonRecoverableMutationFailureIterations = 0
    }

    mutating func updateContinuationIteration(_ iteration: Int) {
        lastContinuationRecoveryIteration = iteration
    }

    mutating func reset() {
        mutatedArtifactPaths = []
        previouslyFailedSignatures = []
        previouslyCompletedSignatures = []
        hasObservedSuccessfulMutation = false
        hasObservedSuccessfulDirectRead = false
        hasObservedMutationVerificationRead = false
        consecutivePostMutationNonMutationIterations = 0
        consecutiveNonRecoverableMutationFailureIterations = 0
        lastContinuationRecoveryIteration = 0
    }
}

struct ToolSetProvider {
    static func mutationRecoveryTools(from available: [AITool]) -> [AITool] {
        available.filter { MutationTools.isMutationTool($0.name) || $0.name == "read_file" }
    }

    static func failedDirectReadRecoveryTools(from available: [AITool]) -> [AITool] {
        let names: Set<String> = ["list_files", "read_file", "write_file", "write_files", "create_file", "delete_file", "replace_in_file", "patch_file"]
        return available.filter { names.contains($0.name) }
    }

    static func mutationOnlyTools(from available: [AITool]) -> [AITool] {
        available.filter { MutationTools.isMutationTool($0.name) }
    }

    static func contentWriteRecoveryTools(from available: [AITool]) -> [AITool] {
        available.filter { MutationTools.contentWriteNames.contains($0.name) }
    }

    static func strictMutationExecutionTools(from available: [AITool]) -> [AITool] {
        available.filter { $0.name == "read_file" || MutationTools.isMutationTool($0.name) }
    }
}
