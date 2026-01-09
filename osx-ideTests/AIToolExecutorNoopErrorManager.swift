import Combine
import Foundation
import SwiftUI
@testable import osx_ide

@MainActor
final class AIToolExecutorNoopErrorManager: ObservableObject, ErrorManagerProtocol {
    @Published var currentError: AppError?
    @Published var showErrorAlert: Bool = false

    func handle(_ error: AppError) { _ = error }
    func handle(_ error: Error, context: String) { _ = error; _ = context }
    func dismissError() { }

    var statePublisher: ObservableObjectPublisher {
        objectWillChange
    }
}
