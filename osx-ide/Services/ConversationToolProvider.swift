import Foundation

@MainActor
final class ConversationToolProvider {
    private let fileSystemService: FileSystemService
    private let eventBus: EventBusProtocol

    private let aiServiceProvider: () -> AIService
    private let codebaseIndexProvider: () -> CodebaseIndexProtocol?
    private let projectRootProvider: () -> URL

    init(
        fileSystemService: FileSystemService,
        eventBus: EventBusProtocol,
        aiServiceProvider: @escaping () -> AIService,
        codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?,
        projectRootProvider: @escaping () -> URL
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
        let projectRoot = projectRootProvider()
        let aiService = aiServiceProvider()
        let codebaseIndex = codebaseIndexProvider()

        var tools: [AITool] = []

        if let codebaseIndex {
            tools.append(IndexFindFilesTool(index: codebaseIndex))
            tools.append(IndexListFilesTool(index: codebaseIndex))
            tools.append(IndexSearchTextTool(index: codebaseIndex))
            tools.append(IndexReadFileTool(index: codebaseIndex))
            tools.append(IndexSearchSymbolsTool(index: codebaseIndex))
        }

        tools.append(
            WriteFileTool(
                fileSystemService: fileSystemService,
                pathValidator: pathValidator,
                eventBus: eventBus
            )
        )
        tools.append(
            WriteFilesTool(
                fileSystemService: fileSystemService,
                pathValidator: pathValidator,
                eventBus: eventBus
            )
        )
        tools.append(CreateFileTool(pathValidator: pathValidator, eventBus: eventBus))
        tools.append(DeleteFileTool(pathValidator: pathValidator, eventBus: eventBus))
        tools.append(
            ReplaceInFileTool(
                fileSystemService: fileSystemService,
                pathValidator: pathValidator,
                eventBus: eventBus
            )
        )
        tools.append(RunCommandTool(projectRoot: projectRoot, pathValidator: pathValidator))

        tools.append(ArchitectAdvisorTool(aiService: aiService, index: codebaseIndex, projectRoot: projectRoot))
        tools.append(PlannerTool())

        tools.append(PatchSetListTool())
        tools.append(PatchSetApplyTool(eventBus: eventBus, projectRoot: projectRoot))
        tools.append(PatchSetClearTool())

        tools.append(CheckpointListTool())
        tools.append(CheckpointRestoreTool(eventBus: eventBus, projectRoot: projectRoot))

        tools.append(ConversationFoldTool(projectRoot: projectRoot))

        return tools
    }
}
