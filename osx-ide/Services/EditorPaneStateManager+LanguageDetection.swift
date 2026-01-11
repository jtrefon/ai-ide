import Foundation

extension EditorPaneStateManager {
    static func languageForFileExtension(_ fileExtension: String) -> String {
        DefaultEditorLanguageDetector().languageForFileExtension(fileExtension)
    }
}
