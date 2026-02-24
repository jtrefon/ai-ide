import Foundation

/// A simple BERT-style tokenizer for embedding models
/// Supports WordPiece tokenization with a vocabulary file
public final class BERTTokenizer: Sendable {
    private let vocabulary: [String: Int]
    private let unkTokenId: Int
    private let clsTokenId: Int
    private let sepTokenId: Int
    private let padTokenId: Int
    private let maxLength: Int
    
    public enum TokenizerError: Error, LocalizedError {
        case vocabularyNotFound
        case invalidVocabularyFormat
        
        public var errorDescription: String? {
            switch self {
            case .vocabularyNotFound:
                return "Vocabulary file not found"
            case .invalidVocabularyFormat:
                return "Invalid vocabulary file format"
            }
        }
    }
    
    /// Initialize with a vocabulary dictionary
    public init(
        vocabulary: [String: Int],
        unkTokenId: Int = 100,
        clsTokenId: Int = 101,
        sepTokenId: Int = 102,
        padTokenId: Int = 0,
        maxLength: Int = 128
    ) {
        self.vocabulary = vocabulary
        self.unkTokenId = unkTokenId
        self.clsTokenId = clsTokenId
        self.sepTokenId = sepTokenId
        self.padTokenId = padTokenId
        self.maxLength = maxLength
    }
    
    /// Load tokenizer from a vocabulary file (vocab.txt)
    public static func load(from url: URL) throws -> BERTTokenizer {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TokenizerError.vocabularyNotFound
        }
        
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var vocabulary: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            let token = line.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }
            vocabulary[token] = index
        }
        
        guard !vocabulary.isEmpty else {
            throw TokenizerError.invalidVocabularyFormat
        }
        
        // Standard BERT special token IDs
        return BERTTokenizer(
            vocabulary: vocabulary,
            unkTokenId: vocabulary["[UNK]"] ?? 100,
            clsTokenId: vocabulary["[CLS]"] ?? 101,
            sepTokenId: vocabulary["[SEP]"] ?? 102,
            padTokenId: vocabulary["[PAD]"] ?? 0
        )
    }
    
    /// Tokenize text and return input IDs, attention mask, and token type IDs
    public func tokenize(_ text: String) -> (inputIds: [Int], attentionMask: [Int], tokenTypeIds: [Int]) {
        // Basic tokenization
        let normalizedText = text.lowercased()
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        
        // WordPiece tokenization (simplified)
        var tokens: [String] = []
        let words = normalizedText.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        
        for word in words {
            let wordTokens = wordpieceTokenize(String(word))
            tokens.append(contentsOf: wordTokens)
        }
        
        // Truncate if needed (reserve 2 for [CLS] and [SEP])
        if tokens.count > maxLength - 2 {
            tokens = Array(tokens.prefix(maxLength - 2))
        }
        
        // Convert to IDs
        var inputIds = [clsTokenId]
        for token in tokens {
            inputIds.append(vocabulary[token] ?? unkTokenId)
        }
        inputIds.append(sepTokenId)
        
        // Create attention mask (1 for real tokens, 0 for padding)
        var attentionMask = Array(repeating: 1, count: inputIds.count)
        
        // Token type IDs (all 0 for single sentence)
        var tokenTypeIds = Array(repeating: 0, count: inputIds.count)
        
        // Pad to maxLength
        let paddingLength = maxLength - inputIds.count
        if paddingLength > 0 {
            inputIds.append(contentsOf: Array(repeating: padTokenId, count: paddingLength))
            attentionMask.append(contentsOf: Array(repeating: 0, count: paddingLength))
            tokenTypeIds.append(contentsOf: Array(repeating: 0, count: paddingLength))
        }
        
        return (inputIds, attentionMask, tokenTypeIds)
    }
    
    /// WordPiece tokenization
    private func wordpieceTokenize(_ word: String) -> [String] {
        var tokens: [String] = []
        var start = word.startIndex
        
        while start < word.endIndex {
            var end = word.endIndex
            var found = false
            
            while end > start {
                let substring = String(word[start..<end])
                let token = tokens.isEmpty ? substring : "##" + substring
                
                if vocabulary[token] != nil {
                    tokens.append(token)
                    found = true
                    break
                }
                end = word.index(before: end)
            }
            
            if !found {
                // Unknown token - use first character as unknown
                if start < word.endIndex {
                    let char = String(word[start])
                    tokens.append(vocabulary[char] != nil ? char : "[UNK]")
                    start = word.index(after: start)
                }
            } else {
                start = end
            }
        }
        
        return tokens.isEmpty ? ["[UNK]"] : tokens
    }
}

/// A simple character-level tokenizer fallback for when vocabulary is not available
public final class SimpleTokenizer: Sendable {
    private let maxLength: Int
    private let vocabulary: [Character: Int]
    
    public init(maxLength: Int = 128) {
        self.maxLength = maxLength
        // Build a simple character vocabulary
        var vocab: [Character: Int] = [:]
        var idx = 4 // Reserve 0-3 for special tokens
        
        // Add ASCII characters
        for i in 32..<127 {
            if let scalar = UnicodeScalar(i) {
                let char = Character(scalar)
                vocab[char] = idx
                idx += 1
            }
        }
        
        self.vocabulary = vocab
    }
    
    public func tokenize(_ text: String) -> (inputIds: [Int], attentionMask: [Int], tokenTypeIds: [Int]) {
        let normalizedText = text.lowercased()
        
        // Convert characters to IDs
        var inputIds: [Int] = [1] // CLS token
        for char in normalizedText {
            inputIds.append(vocabulary[char] ?? 2) // 2 is UNK
        }
        inputIds.append(2) // SEP token
        
        // Truncate if needed
        if inputIds.count > maxLength {
            inputIds = Array(inputIds.prefix(maxLength))
        }
        
        // Create attention mask
        var attentionMask = Array(repeating: 1, count: inputIds.count)
        
        // Token type IDs
        var tokenTypeIds = Array(repeating: 0, count: inputIds.count)
        
        // Pad to maxLength
        let paddingLength = maxLength - inputIds.count
        if paddingLength > 0 {
            inputIds.append(contentsOf: Array(repeating: 0, count: paddingLength))
            attentionMask.append(contentsOf: Array(repeating: 0, count: paddingLength))
            tokenTypeIds.append(contentsOf: Array(repeating: 0, count: paddingLength))
        }
        
        return (inputIds, attentionMask, tokenTypeIds)
    }
}
