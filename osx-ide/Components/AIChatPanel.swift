import SwiftUI

/// An AI chat panel that uses the user's code selection as context for AI queries and displays responses.
struct AIChatPanel: View {
    @ObservedObject var selectionContext: CodeSelectionContext
    @State private var message: String = ""
    @State private var aiResponse: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Assistant")
                .font(.headline)
            if let selected = currentSelection, !selected.isEmpty {
                Text("Context: \"\(selected)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                TextField("Ask a question (AI will use selected code as context)", text: $message)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: sendToAI) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Send")
                    }
                }
                .disabled(message.isEmpty || isLoading)
            }
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            if !aiResponse.isEmpty {
                Text("AI Response:")
                    .font(.subheadline)
                Text(aiResponse)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                    .font(.system(.body, design: .monospaced))
            }
            Spacer()
        }
        .padding()
        .accessibilityIdentifier("AIChatPanel")
    }

    var currentSelection: String? { selectionContext.selectedText }

    func sendToAI() {
        isLoading = true
        errorMessage = nil
        aiResponse = ""
        Task {
            do {
                // This should be replaced by a real AIService implementation
                let response = try await SampleAIService().sendMessage(message, context: selectionContext.selectedText)
                aiResponse = response
            } catch {
                errorMessage = "AI request failed: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

#Preview {
    let ctx = CodeSelectionContext()
    ctx.selectedText = "func helloWorld() { print(\"Hello\") }"
    return AIChatPanel(selectionContext: ctx)
}

