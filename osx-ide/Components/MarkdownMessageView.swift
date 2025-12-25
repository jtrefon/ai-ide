import SwiftUI

struct MarkdownMessageView: View {
    let content: String

    var body: some View {
        MarkdownView(markdown: content) { code, language in
            CodePreviewView(
                code: code,
                language: language,
                title: language?.capitalized ?? "Code"
            )
        }
    }
}
