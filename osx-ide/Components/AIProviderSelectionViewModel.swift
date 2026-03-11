import Foundation

@MainActor
final class AIProviderSelectionViewModel: ObservableObject {
    @Published var selectedProvider: RemoteAIProvider {
        didSet {
            persistSelection()
        }
    }

    private let selectionStore: AIProviderSelectionStore

    init(selectionStore: AIProviderSelectionStore = AIProviderSelectionStore()) {
        self.selectionStore = selectionStore
        self.selectedProvider = .openRouter
        Task {
            let provider = await selectionStore.selectedRemoteProvider()
            await MainActor.run {
                self.selectedProvider = provider
            }
        }
    }

    private func persistSelection() {
        let provider = selectedProvider
        Task {
            await selectionStore.setSelectedRemoteProvider(provider)
        }
    }
}
