import Foundation

struct LocalModelCatalogItem: Identifiable, Hashable {
    let id: String
    let displayName: String
    let huggingFaceRepository: String
    let revision: String
    let files: [String]
    let supportedQuantizations: [LocalModelQuantization]
    let contextLength: Int?

    init(
        id: String,
        displayName: String,
        huggingFaceRepository: String,
        revision: String = "main",
        files: [String],
        supportedQuantizations: [LocalModelQuantization],
        contextLength: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.huggingFaceRepository = huggingFaceRepository
        self.revision = revision
        self.files = files
        self.supportedQuantizations = supportedQuantizations
        self.contextLength = contextLength
    }

    func huggingFaceFileURL(filePath: String) -> URL? {
        URL(string: "https://huggingface.co/\(huggingFaceRepository)/resolve/\(revision)/\(filePath)")
    }
}

enum LocalModelCatalog {
    static let defaultModelId = "granite-4.0-micro-mlx-8bit"

    static let items: [LocalModelCatalogItem] = [
        LocalModelCatalogItem(
            id: defaultModelId,
            displayName: "Granite 4.0 Micro (MLX 8-bit)",
            huggingFaceRepository: "mlx-community/granite-4.0-micro-8bit",
            revision: "968b66c",
            files: [
                "config.json",
                "special_tokens_map.json",
                "generation_config.json",
                "chat_template.jinja",
                "tokenizer.json",
                "tokenizer_config.json",
                "merges.txt",
                "vocab.json",
                "model.safetensors",
                "model.safetensors.index.json"
            ],
            supportedQuantizations: [.q8],
            contextLength: 4096
        )
    ]

    static func item(id: String) -> LocalModelCatalogItem? {
        items.first(where: { $0.id == id })
    }
}
