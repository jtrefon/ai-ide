import Foundation

@MainActor
protocol ShellManaging: AnyObject {
    var delegate: ShellManagerDelegate? { get set }
    func start(in directory: URL?)
    func sendInput(_ text: String)
    func interrupt()
    func terminate()
}
