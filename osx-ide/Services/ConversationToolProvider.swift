import Foundation

@MainActor
final class ConversationToolProvider {
    private let fileSystemService: FileSystemService
    private let eventBus: EventBusProtocol

    private let aiServiceProvider: () -> AIService?
    private let codebaseIndexProvider: () -> CodebaseIndexProtocol?
    private let projectRootProvider: () -> URL?

    init(
        fileSystemService: FileSystemService,
        eventBus: EventBusProtocol,
        aiServiceProvider: @escaping () -> AIService?,
        codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?,
        projectRootProvider: @escaping () -> URL?
    ) {
        self.fileSystemService = fileSystemService
        self.eventBus = eventBus
        self.aiServiceProvider = aiServiceProvider
        self.codebaseIndexProvider = codebaseIndexProvider
        self.projectRootProvider = projectRootProvider
    }

    func availableTools(mode: AIMode, pathValidator: PathValidator) -> [AITool] {
        mode.allowedTools(from: allTools(pathValidator: pathValidator))
    }

    func allTools(pathValidator: PathValidator) -> [AITool] {
        guard let projectRoot = projectRootProvider() else { return [] }
        
        var tools: [AITool] = []

        // Core Filesystem Tools
        tools.append(ReadFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator))
        tools.append(ListFilesTool(pathValidator: pathValidator))
        tools.append(WriteFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator, eventBus: eventBus))
        tools.append(ReplaceInFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator, eventBus: eventBus))
        tools.append(DeleteFileTool(pathValidator: pathValidator, eventBus: eventBus))
        
        // RAG & Index Tools
        if let index = codebaseIndexProvider() {
            tools.append(IndexSearchTextTool(index: index))
            tools.append(IndexSearchSymbolsTool(index: index))
            tools.append(IndexFindFilesTool(index: index))
            tools.append(IndexListFilesTool(index: index))
            tools.append(IndexReadFileTool(index: index))
            tools.append(IndexListMemoriesTool(index: index))
            tools.append(IndexAddMemoryTool(index: index))
        }

        // Search & Structure Tools
        tools.append(SearchProjectTool(index: codebaseIndexProvider(), projectRoot: projectRoot))
        tools.append(GrepTool(pathValidator: pathValidator))
        tools.append(FindFileTool(pathValidator: pathValidator))
        tools.append(GetProjectStructureTool(projectRoot: projectRoot))

        // Terminal & Execution
        tools.append(RunCommandTool(projectRoot: projectRoot, pathValidator: pathValidator))

        return tools
    }
}
