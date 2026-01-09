import Foundation

@MainActor
protocol WorkspaceServiceProtocol: AnyObject, StatePublisherProtocol {
    var currentDirectory: URL? { get set }
    func createFile(named name: String, in directory: URL)
    func createFolder(named name: String, in directory: URL)
    func deleteItem(at url: URL)
    func renameItem(at url: URL, to newName: String) -> URL?
    func navigateToParent()
    func navigateTo(subdirectory: String)
    func isValidPath(_ path: String) -> Bool
    func makePathValidator(projectRoot: URL) -> PathValidator
    func makePathValidatorForCurrentDirectory() -> PathValidator?
    func handleError(_ error: AppError)
}
