import Foundation

/// List files in a directory
struct ListFilesTool: AITool {
    let name = "list_files"
    let description = "List files and directories in the specified path."
    var parameters: [String: Any] {
        FileToolParameterSchemaBuilder.objectSchema(
            properties: [
                "path": FileToolParameterSchemaBuilder.pathProperty(
                    description: "The absolute path to the directory."
                )
            ],
            required: ["path"]
        )
    }
    let pathValidator: PathValidator

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for list_files")
        }
        let url = try pathValidator.validateAndResolve(path)
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let fileNames = contents.map { $0.lastPathComponent }
        return fileNames.joined(separator: "\n")
    }
}
