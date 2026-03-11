import XCTest

@testable import osx_ide

final class LocalModelFileStoreTests: XCTestCase {
    private let qwen35ModelId = "mlx-community/Qwen3.5-4B-MLX-4bit@main"

    override func tearDownWithError() throws {
        try LocalModelFileStore.deleteModelDirectory(modelId: qwen35ModelId)
        try super.tearDownWithError()
    }

    func testContextLengthReadsNestedTextConfigForQwen35() throws {
        let model = try XCTUnwrap(LocalModelCatalog.model(id: qwen35ModelId))
        try installQwen35FixtureConfig()

        XCTAssertEqual(LocalModelFileStore.contextLength(for: model), 262144)
    }

    func testRuntimeModelDirectoryNormalizesQwen35ConfigForCurrentMLXRuntime() throws {
        let model = try XCTUnwrap(LocalModelCatalog.model(id: qwen35ModelId))
        try installQwen35FixtureConfig()
        try installPlaceholderArtifact(named: "model.safetensors")
        try installPlaceholderArtifact(named: "tokenizer.json")

        let runtimeDirectory = try LocalModelFileStore.runtimeModelDirectory(for: model)
        let runtimeConfigURL = runtimeDirectory.appendingPathComponent("config.json")
        let runtimeConfigData = try Data(contentsOf: runtimeConfigURL)
        let runtimeConfigObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: runtimeConfigData) as? [String: Any]
        )

        XCTAssertEqual(runtimeDirectory.lastPathComponent, "osx-ide-runtime")
        XCTAssertEqual(runtimeConfigObject["model_type"] as? String, "qwen3")
        XCTAssertNil(runtimeConfigObject["text_config"])
        XCTAssertEqual(runtimeConfigObject["max_position_embeddings"] as? Int, 262144)
        XCTAssertEqual(runtimeConfigObject["hidden_size"] as? Int, 2560)

        let runtimeTokenizerURL = runtimeDirectory.appendingPathComponent("tokenizer.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeTokenizerURL.path))
    }

    private func installQwen35FixtureConfig() throws {
        let modelDirectory = try LocalModelFileStore.modelDirectory(modelId: qwen35ModelId)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let config = """
        {
          "architectures": ["Qwen3_5ForConditionalGeneration"],
          "model_type": "qwen3_5",
          "image_token_id": 248056,
          "text_config": {
            "model_type": "qwen3",
            "max_position_embeddings": 262144,
            "hidden_size": 2560,
            "intermediate_size": 9216,
            "num_hidden_layers": 32,
            "num_attention_heads": 32,
            "num_key_value_heads": 8,
            "rms_norm_eps": 0.000001,
            "vocab_size": 151936,
            "head_dim": 256,
            "rope_theta": 1000000,
            "tie_word_embeddings": false
          },
          "quantization": {
            "group_size": 64,
            "bits": 4,
            "mode": "affine"
          }
        }
        """

        try config.write(
            to: modelDirectory.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func installPlaceholderArtifact(named fileName: String) throws {
        let artifactURL = try LocalModelFileStore.artifactURL(modelId: qwen35ModelId, fileName: fileName)
        try Data("fixture".utf8).write(to: artifactURL)
    }
}
