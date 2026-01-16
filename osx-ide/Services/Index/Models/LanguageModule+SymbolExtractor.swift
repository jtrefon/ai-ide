import Foundation

public extension LanguageModule {
    var symbolExtractor: AnySymbolExtractor {
        AnySymbolExtractor { content, resourceId in
            parseSymbols(content: content, resourceId: resourceId)
        }
    }
}
