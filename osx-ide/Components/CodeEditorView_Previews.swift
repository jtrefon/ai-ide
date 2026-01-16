import SwiftUI

struct CodeEditorView_Previews: PreviewProvider {
    static var previews: some View {
        CodeEditorView(
            text: .constant("func helloWorld() {\n    print(\"Hello, World!\")\n}"),
            language: "swift",
            selectedRange: .constant(nil),
            selectionContext: CodeSelectionContext(),
            showLineNumbers: true,
            wordWrap: false,
            fontSize: AppConstantsEditor.defaultFontSize,
            fontFamily: AppConstantsEditor.defaultFontFamily
        )
        .frame(height: 300)
    }
}
