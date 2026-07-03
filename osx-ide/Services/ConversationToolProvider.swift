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
        tools.append(PatchFileToolAdapter(projectRoot: projectRoot))
        tools.append(DeleteFileTool(pathValidator: pathValidator, eventBus: eventBus))
        
        // Pinned Rules Tools
        tools.append(PinnedRuleAddTool(projectRoot: projectRoot))
        tools.append(PinnedRuleRemoveTool(projectRoot: projectRoot))
        tools.append(PinnedRuleListTool(projectRoot: projectRoot))

        // Symbol Lookup Tools
        let databaseStore = codebaseIndexProvider()?.database
        if let db = databaseStore {
            tools.append(LocateSymbolTool(databaseProvider: { db }))
            tools.append(InspectSymbolTool(databaseProvider: { db }))
            tools.append(WhereSymbolTool(databaseProvider: { db }))
        }

        // Search & Structure Tools
        tools.append(SearchProjectTool(index: codebaseIndexProvider(), projectRoot: projectRoot))
        tools.append(LocalFindTool(index: codebaseIndexProvider(), projectRoot: projectRoot))
        tools.append(GoogleWebSearchTool())
        tools.append(WebBrowseTool())
        tools.append(GrepTool(pathValidator: pathValidator))
        tools.append(FindFileTool(pathValidator: pathValidator))
        tools.append(GetProjectStructureTool(projectRoot: projectRoot))

        // Terminal & Execution
        tools.append(RunCommandTool(projectRoot: projectRoot, pathValidator: pathValidator))

        // Planning & Task Management
        tools.append(PlanTool())
        

        return tools
    }
}
