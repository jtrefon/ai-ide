import SwiftUI

struct CodePreviewView: View {
    let code: String
    let language: String?
    let title: String
    var fontSize: Double
    var fontFamily: String
    @State private var isCopied = false

    init(
        code: String,
        language: String? = nil,
        title: String = "Code Preview",
        fontSize: Double = 12,
        fontFamily: String = AppConstants.Editor.defaultFontFamily
    ) {
        self.code = code
        self.language = language
        self.title = title
        self.fontSize = fontSize
        self.fontFamily = fontFamily
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            highlightedText
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
        }
        .padding(.top, 4)
    }

    private var header: some View {
        HStack {
            SwiftUI.Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let language = language {
                SwiftUI.Text("\u{2022}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SwiftUI.Text(language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
            }

            Spacer()

            Button(action: copyCode) {
                HStack {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    SwiftUI.Text(isCopied ? "Copied!" : "Copy")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private var highlightedText: some View {
        if let attributed = highlightedAttributedString {
            SwiftUI.Text(attributed)
        } else {
            SwiftUI.Text(code)
                .font(resolveFont(size: fontSize, family: fontFamily))
        }
    }

    private var highlightedAttributedString: AttributedString? {
        guard let language = language, let codeLanguage = codeLanguage(from: language) else {
            return nil
        }
        guard let module = LanguageModuleManager.shared.getHighlightModule(for: codeLanguage) else {
            return nil
        }
        let nsFont = resolveNSFont(size: fontSize, family: fontFamily)
        let nsAttributed = module.highlight(code, font: nsFont)
        return AttributedString(nsAttributed)
    }

    private func codeLanguage(from alias: String) -> CodeLanguage? {
        let lowercased = alias.lowercased()
        let aliasMap: [String: CodeLanguage] = [
            "js": .javascript,
            "ts": .typescript,
            "jsx": .tsx,
            "tsx": .tsx,
            "py": .python,
            "yaml": .yaml,
            "yml": .yaml,
            "md": .markdown,
            "json": .json,
            "txt": .unknown,
            "sh": .unknown,
            "bash": .unknown,
            "zsh": .unknown,
            "shell": .unknown,
            "console": .unknown,
            "text": .unknown,
            "swift": .swift,
            "javascript": .javascript,
            "typescript": .typescript,
            "python": .python,
            "html": .html,
            "css": .css,
        ]
        if let mapped = aliasMap[lowercased] {
            return mapped
        }
        return CodeLanguage(rawValue: lowercased)
    }

    private func resolveFont(size: Double, family: String) -> Font {
        if let nsFont = NSFont(name: family, size: CGFloat(size)) {
            return Font(nsFont)
        }
        return .system(size: CGFloat(size), weight: .regular, design: .monospaced)
    }

    private func resolveNSFont(size: Double, family: String) -> NSFont {
        if let nsFont = NSFont(name: family, size: CGFloat(size)) {
            return nsFont
        }
        return .monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }

    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)

        isCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                isCopied = false
            }
        }
    }
}

struct CodePreviewView_Previews: PreviewProvider {
    static var previews: some View {
        CodePreviewView(
            code: "func helloWorld() {\n    print(\"Hello, World!\")\n}",
            fontSize: 12,
            fontFamily: AppConstants.Editor.defaultFontFamily
        )
        .padding()
    }
}
