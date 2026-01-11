import Foundation

@MainActor
final class EditingStateManager {
    private let languageDetector: EditorLanguageDetecting

    init(languageDetector: EditorLanguageDetecting) {
        self.languageDetector = languageDetector
    }

    func updateEditorContent(
        newContent: String,
        selectedFile: String?,
        currentLanguage: String,
        applyContent: (String) -> Void,
        applyLanguage: (String) -> Void,
        updateServiceContent: (String) -> Void
    ) {
        applyContent(newContent)
        updateServiceContent(newContent)

        guard selectedFile == nil else { return }
        guard let detected = languageDetector.detectLanguageForUntitledContent(
            currentLanguage: currentLanguage,
            content: newContent
        ) else { return }

        applyLanguage(detected)
    }

    func setEditorLanguage(
        language: String,
        applyLanguage: (String) -> Void,
        updateServiceLanguage: (String) -> Void
    ) {
        applyLanguage(language)
        updateServiceLanguage(language)
    }
}
