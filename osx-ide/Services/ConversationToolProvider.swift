import Foundation

@MainActor
final class ConversationToolProvider {
    private let fileSystemService: FileSystemService
    private let eventBus: EventBusProtocol
    private let vectorStoreService: VectorStoreService?
    private let embedder: (any MemoryEmbeddingGenerating)?

    private let aiServiceProvider: () -> AIService?
    private let codebaseIndexProvider: () -> CodebaseIndexProtocol?
    private let projectRootProvider: () -> URL?

    init(
        fileSystemService: FileSystemService,
        eventBus: EventBusProtocol,
        vectorStoreService: VectorStoreService?,
        embedder: (any MemoryEmbeddingGenerating)?,
        aiServiceProvider: @escaping () -> AIService?,
        codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?,
        projectRootProvider: @escaping () -> URL?
    ) {
        self.fileSystemService = fileSystemService
        self.eventBus = eventBus
        self.vectorStoreService = vectorStoreService
        self.embedder = embedder
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
        tools.append(PatchFileToolAdapter(projectRoot: projectRoot))
        tools.append(DeleteFileTool(pathValidator: pathValidator, eventBus: eventBus))
        
        // Pinned Rules Tools
        tools.append(PinnedRuleAddTool(projectRoot: projectRoot))
        tools.append(PinnedRuleRemoveTool(projectRoot: projectRoot))
        tools.append(PinnedRuleListTool(projectRoot: projectRoot))

        // Context / Memory Tools
        tools.append(ContextTool(vectorStoreService: vectorStoreService, embedder: embedder))

        // Search & Structure Tools
        tools.append(SearchProjectTool(index: codebaseIndexProvider(), projectRoot: projectRoot))
        tools.append(GoogleWebSearchTool())
        tools.append(WebBrowseTool())
        tools.append(FindFileTool(pathValidator: pathValidator))

        // Terminal & Execution
        tools.append(RunCommandTool(projectRoot: projectRoot, pathValidator: pathValidator))

        // Planning & Task Management
        tools.append(PlanTool())

        // Research Subagent (Context Access Layer L6)
        tools.append(ResearchTool(
            aiServiceProvider: aiServiceProvider,
            projectRootProvider: projectRootProvider,
            fileSystemService: fileSystemService,
            pathValidator: pathValidator,
            vectorStoreService: vectorStoreService,
            embedder: embedder,
            codebaseIndexProvider: codebaseIndexProvider
        ))

        return tools
    }
}
