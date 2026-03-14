import Foundation

public enum LocalModelFileStore {
    enum LocalModelFileStoreError: Error, LocalizedError {
        case missingRequiredRuntimeArtifact(modelId: String, fileName: String)

        var errorDescription: String? {
            switch self {
            case let .missingRequiredRuntimeArtifact(modelId, fileName):
                return "Required runtime artifact \(fileName) is missing for model \(modelId)."
            }
        }
    }
    struct ModelConfig: Codable {
        let maxPositionEmbeddings: Int?
        let maxSequenceLength: Int?
        let modelType: String?
        let textConfig: TextConfig?

        struct TextConfig: Codable {
            let maxPositionEmbeddings: Int?
            let maxSequenceLength: Int?
            let modelType: String?

            enum CodingKeys: String, CodingKey {
                case maxPositionEmbeddings = "max_position_embeddings"
                case maxSequenceLength = "max_sequence_length"
                case modelType = "model_type"
            }
        }

        enum CodingKeys: String, CodingKey {
            case maxPositionEmbeddings = "max_position_embeddings"
            case maxSequenceLength = "max_sequence_length"
            case modelType = "model_type"
            case textConfig = "text_config"
        }

        var contextLength: Int? {
            maxPositionEmbeddings
                ?? maxSequenceLength
                ?? textConfig?.maxPositionEmbeddings
                ?? textConfig?.maxSequenceLength
        }

        var effectiveModelType: String? {
            modelType ?? textConfig?.modelType
        }
    }

    public static func modelsRootDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let root =
            appSupport
            .appendingPathComponent("osx-ide", isDirectory: true)
            .appendingPathComponent("local-models", isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func modelDirectory(modelId: String) throws -> URL {
        let sanitized = sanitizeModelId(modelId)
        return try modelsRootDirectory().appendingPathComponent(sanitized, isDirectory: true)
    }

    static func artifactURL(modelId: String, fileName: String) throws -> URL {
        try modelDirectory(modelId: modelId).appendingPathComponent(fileName, isDirectory: false)
    }

    static func runtimeModelDirectory(for model: LocalModelDefinition) throws -> URL {
        let installedDirectory = try ensureCanonicalInstallation(for: model)
        guard requiresRuntimeCompatibilityDirectory(model: model) else {
            return installedDirectory
        }

        return try prepareRuntimeCompatibilityDirectory(
            sourceDirectory: installedDirectory,
            model: model
        )
    }

    static func isModelInstalled(_ model: LocalModelDefinition) -> Bool {
        _ = try? ensureCanonicalInstallation(for: model)
        return hasAllArtifacts(for: model, in: try? modelDirectory(modelId: model.id))
    }

    static func deleteModelDirectory(modelId: String) throws {
        let dir = try modelDirectory(modelId: modelId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    static func loadModelConfig(modelId: String) -> ModelConfig? {
        guard let configURL = try? artifactURL(modelId: modelId, fileName: "config.json"),
            FileManager.default.fileExists(atPath: configURL.path),
            let data = try? Data(contentsOf: configURL),
            let config = try? JSONDecoder().decode(ModelConfig.self, from: data)
        else {
            return nil
        }
        return config
    }

    static func contextLength(for model: LocalModelDefinition) -> Int {
        _ = try? ensureCanonicalInstallation(for: model)
        // Try to load from config.json first
        if let config = loadModelConfig(modelId: model.id),
            let contextLength = config.contextLength
        {
            return contextLength
        }
        // Fall back to definition default
        return model.defaultContextLength
    }

    @discardableResult
    static func ensureCanonicalInstallation(for model: LocalModelDefinition) throws -> URL {
        let canonicalDirectory = try modelDirectory(modelId: model.id)
        try materializeCanonicalSymlinkIfNeeded(for: model, canonicalDirectory: canonicalDirectory)
        try migrateLegacyCacheIfNeeded(for: model, canonicalDirectory: canonicalDirectory)
        return canonicalDirectory
    }

    private static func requiresRuntimeCompatibilityDirectory(model: LocalModelDefinition) -> Bool {
        // The upgraded mlx-swift-lm runtime supports Qwen 3.5 natively, including its
        // multimodal configuration and processor stack. Keep the compatibility path for
        // older-model shims only; Qwen 3.5 should now load from the installed directory.
        false
    }

    private static func hasAllArtifacts(for model: LocalModelDefinition, in directory: URL?) -> Bool {
        guard let directory else { return false }
        let fileManager = FileManager.default
        for artifact in model.artifacts {
            let artifactPath = directory.appendingPathComponent(artifact.fileName, isDirectory: false).path
            if !fileManager.fileExists(atPath: artifactPath) {
                return false
            }
        }
        return true
    }

    private static func materializeCanonicalSymlinkIfNeeded(
        for model: LocalModelDefinition,
        canonicalDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        guard isSymbolicLink(at: canonicalDirectory) else { return }

        let symlinkTarget = try resolvedSymlinkTarget(at: canonicalDirectory)
        let targetDirectory = symlinkTarget.standardizedFileURL

        guard hasAllArtifacts(for: model, in: targetDirectory) else { return }

        try fileManager.removeItem(at: canonicalDirectory)
        if fileManager.fileExists(atPath: canonicalDirectory.path) {
            try fileManager.removeItem(at: canonicalDirectory)
        }
        try fileManager.moveItem(at: targetDirectory, to: canonicalDirectory)
    }

    private static func migrateLegacyCacheIfNeeded(
        for model: LocalModelDefinition,
        canonicalDirectory: URL
    ) throws {
        guard !hasAllArtifacts(for: model, in: canonicalDirectory) else { return }
        guard let legacyDirectory = legacyCacheDirectory(for: model) else { return }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacyDirectory.path),
              hasAllArtifacts(for: model, in: legacyDirectory) else {
            return
        }

        if fileManager.fileExists(atPath: canonicalDirectory.path) {
            try fileManager.removeItem(at: canonicalDirectory)
        }

        let canonicalParent = canonicalDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: canonicalParent, withIntermediateDirectories: true)
        try fileManager.moveItem(at: legacyDirectory, to: canonicalDirectory)
    }

    private static func legacyCacheDirectory(for model: LocalModelDefinition) -> URL? {
        guard let artifactURL = model.artifacts.first?.url,
              artifactURL.host == "huggingface.co" else {
            return nil
        }

        let pathComponents = artifactURL.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 4,
              pathComponents[2] == "resolve" else {
            return nil
        }

        let owner = pathComponents[0]
        let repository = pathComponents[1]
        guard let cachesRoot = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }

        return cachesRoot
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(owner, isDirectory: true)
            .appendingPathComponent(repository, isDirectory: true)
    }

    private static func isSymbolicLink(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else {
            return false
        }
        return values.isSymbolicLink == true
    }

    private static func resolvedSymlinkTarget(at symlinkURL: URL) throws -> URL {
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: symlinkURL.path)
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination, isDirectory: true)
        }
        return symlinkURL.deletingLastPathComponent()
            .appendingPathComponent(destination, isDirectory: true)
    }

    private static func prepareRuntimeCompatibilityDirectory(
        sourceDirectory: URL,
        model: LocalModelDefinition
    ) throws -> URL {
        let runtimeDirectory = sourceDirectory.appendingPathComponent("osx-ide-runtime", isDirectory: true)
        let normalizedChatTemplate = try normalizedRuntimeChatTemplateData(for: model)

        if FileManager.default.fileExists(atPath: runtimeDirectory.path) {
            try FileManager.default.removeItem(at: runtimeDirectory)
        }
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)

        let fileManager = FileManager.default
        try validateRequiredRuntimeArtifacts(for: model, in: sourceDirectory)
        let sourceContents = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for sourceItem in sourceContents {
            guard sourceItem.lastPathComponent != runtimeDirectory.lastPathComponent else {
                continue
            }
            guard sourceItem.lastPathComponent != "config.json",
                  sourceItem.lastPathComponent != "chat_template.jinja" else {
                continue
            }

            let destinationItem = runtimeDirectory.appendingPathComponent(sourceItem.lastPathComponent)
            try fileManager.createSymbolicLink(at: destinationItem, withDestinationURL: sourceItem)
        }

        try normalizedRuntimeConfigData(for: model).write(
            to: runtimeDirectory.appendingPathComponent("config.json"),
            options: Data.WritingOptions.atomic
        )
        try normalizedChatTemplate.write(
            to: runtimeDirectory.appendingPathComponent("chat_template.jinja"),
            options: Data.WritingOptions.atomic
        )
        return runtimeDirectory
    }

    private static func validateRequiredRuntimeArtifacts(for model: LocalModelDefinition, in directory: URL) throws {
        let requiredArtifacts = requiredRuntimeArtifacts(for: model)
        guard !requiredArtifacts.isEmpty else { return }

        let fileManager = FileManager.default
        for artifact in requiredArtifacts {
            let path = directory.appendingPathComponent(artifact).path
            guard fileManager.fileExists(atPath: path) else {
                throw LocalModelFileStoreError.missingRequiredRuntimeArtifact(
                    modelId: model.id,
                    fileName: artifact
                )
            }
        }
    }

    private static func requiredRuntimeArtifacts(for model: LocalModelDefinition) -> [String] {
        guard model.id == "mlx-community/Qwen3.5-4B-MLX-4bit@main" else {
            return []
        }

        return [
            "preprocessor_config.json",
            "processor_config.json",
            "video_preprocessor_config.json",
            "tokenizer.json",
            "tokenizer_config.json"
        ]
    }

    private static func normalizedRuntimeConfigData(for model: LocalModelDefinition) throws -> Data {
        let configURL = try artifactURL(modelId: model.id, fileName: "config.json")
        let originalData = try Data(contentsOf: configURL)

        guard model.id == "mlx-community/Qwen3.5-4B-MLX-4bit@main" else {
            return originalData
        }

        guard var configObject = try JSONSerialization.jsonObject(with: originalData) as? [String: Any] else {
            return originalData
        }

        var mutated = false

        if let modelType = configObject["model_type"] as? String,
           modelType == "qwen3_5" {
            configObject["model_type"] = "qwen3_vl"
            mutated = true
        }

        if let textConfig = configObject["text_config"] as? [String: Any] {
            configObject["text_config"] = textConfig
        }

        guard mutated else { return originalData }
        return try JSONSerialization.data(withJSONObject: configObject, options: [.prettyPrinted])
    }

    private static func normalizedRuntimeChatTemplateData(for model: LocalModelDefinition) throws -> Data {
        if model.id == "mlx-community/Qwen3.5-4B-MLX-4bit@main" {
            return Data(qwen35JSONOnlyChatTemplate.utf8)
        }

        let templateURL = try artifactURL(modelId: model.id, fileName: "chat_template.jinja")
        return try Data(contentsOf: templateURL)
    }

    private static let qwen35JSONOnlyChatTemplate = #"""
{%- if tools %}
    {{- '<|im_start|>system\n' }}
    {%- if messages[0].role == 'system' %}
        {{- messages[0].content + '\n\n' }}
    {%- endif %}
    {{- '# Tools\n\nYou have access to the following functions.\nReturn tool calls as JSON only. Do not use XML, HTML, or tag wrappers.\n\n' }}
    {%- for tool in tools %}
        {{- tool | tojson + '\n' }}
    {%- endfor %}
    {{- '\nIf you choose to call a function, reply with a single JSON object and no trailing text.\nFormat:\n{"tool_calls":[{"name":"function_name","arguments":{"parameter":"value"}}]}' }}
    {{- '<|im_end|>\n' }}
{%- else %}
    {%- if messages[0].role == 'system' %}
        {{- '<|im_start|>system\n' + messages[0].content + '<|im_end|>\n' }}
    {%- endif %}
{%- endif %}
{%- for message in messages %}
    {%- if message.content is string %}
        {%- set content = message.content %}
    {%- else %}
        {%- set content = '' %}
    {%- endif %}
    {%- if (message.role == "user") or (message.role == "system" and not loop.first) %}
        {{- '<|im_start|>' + message.role + '\n' + content + '<|im_end|>\n' }}
    {%- elif message.role == "assistant" %}
        {{- '<|im_start|>' + message.role + '\n' + content }}
        {%- if message.tool_calls %}
            {%- for tool_call in message.tool_calls %}
                {%- if (loop.first and content) or (not loop.first) %}
                    {{- '\n' }}
                {%- endif %}
                {%- if tool_call.function %}
                    {%- set tool_call = tool_call.function %}
                {%- endif %}
                {{- '{"tool_calls":[{"name":"' }}
                {{- tool_call.name }}
                {{- '","arguments":' }}
                {%- if tool_call.arguments is string %}
                    {{- tool_call.arguments }}
                {%- else %}
                    {{- tool_call.arguments | tojson }}
                {%- endif %}
                {{- '}}]}' }}
            {%- endfor %}
        {%- endif %}
        {{- '<|im_end|>\n' }}
    {%- elif message.role == "tool" %}
        {{- '<|im_start|>user\nTool Output:\n' + content + '<|im_end|>\n' }}
    {%- endif %}
{%- endfor %}
{%- if add_generation_prompt %}
    {{- '<|im_start|>assistant\n' }}
{%- endif %}
"""#

    private static func sanitizeModelId(_ modelId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = modelId.unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(scalar)
            }
            return "_"
        }
        return String(mapped)
    }
}
