import Foundation

struct LocalModelInferenceConfiguration: Sendable, Equatable, Hashable {
    let contextLength: Int
    let maxKVSize: Int
    let maxOutputTokens: Int
    let prefillStepSize: Int

    var cacheKind: String {
        maxKVSize < contextLength ? "rotating-window" : "rotating-full"
    }

    var label: String {
        "ctx\(contextLength)-kv\(maxKVSize)-out\(maxOutputTokens)-prefill\(prefillStepSize)"
    }
}

struct LocalModelInferenceOverrides: Sendable, Equatable {
    var contextLength: Int?
    var maxKVSize: Int?
    var maxOutputTokens: Int?
    var prefillStepSize: Int?

    static let shared = Store()

    actor Store {
        private var overrides: LocalModelInferenceOverrides?

        func set(_ overrides: LocalModelInferenceOverrides?) {
            self.overrides = overrides
        }

        func clear() {
            overrides = nil
        }

        func current() -> LocalModelInferenceOverrides? {
            overrides
        }

        func resolve(defaultContextLength: Int, defaultMaxOutputTokens: Int) -> LocalModelInferenceConfiguration {
            Self.resolve(
                defaultContextLength: defaultContextLength,
                defaultMaxOutputTokens: defaultMaxOutputTokens,
                environment: ProcessInfo.processInfo.environment,
                overrides: overrides
            )
        }

        nonisolated private static func resolve(
            defaultContextLength: Int,
            defaultMaxOutputTokens: Int,
            environment: [String: String],
            overrides: LocalModelInferenceOverrides?
        ) -> LocalModelInferenceConfiguration {
            let envContext = parseInt(environment["OSXIDE_LOCAL_MODEL_CONTEXT_LENGTH"])
            let envMaxKV = parseInt(environment["OSXIDE_LOCAL_MODEL_MAX_KV_SIZE"])
            let envMaxOutput = parseInt(environment["OSXIDE_LOCAL_MODEL_MAX_OUTPUT_TOKENS"])
            let envPrefill = parseInt(environment["OSXIDE_LOCAL_MODEL_PREFILL_STEP_SIZE"])

            let contextLength = clamp(
                overrides?.contextLength ?? envContext ?? defaultContextLength,
                min: 256,
                max: 32_768
            )
            let maxKVSize = clamp(
                overrides?.maxKVSize ?? envMaxKV ?? contextLength,
                min: 256,
                max: contextLength
            )
            let maxOutputTokens = clamp(
                overrides?.maxOutputTokens ?? envMaxOutput ?? defaultMaxOutputTokens,
                min: 64,
                max: 8_192
            )
            let prefillStepSize = clamp(
                overrides?.prefillStepSize ?? envPrefill ?? 512,
                min: 64,
                max: 4_096
            )

            return LocalModelInferenceConfiguration(
                contextLength: contextLength,
                maxKVSize: maxKVSize,
                maxOutputTokens: maxOutputTokens,
                prefillStepSize: prefillStepSize
            )
        }

        nonisolated private static func parseInt(_ rawValue: String?) -> Int? {
            guard let rawValue else {
                return nil
            }

            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(trimmed) else {
                return nil
            }
            return value
        }

        nonisolated private static func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
            Swift.max(minimum, Swift.min(value, maximum))
        }
    }
}
