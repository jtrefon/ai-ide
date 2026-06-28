// Copyright © 2024 Apple Inc.

import MLX
import MLXLMCommon

/// Marker protocol for LLMModels
public protocol LLMModel: LanguageModel, LoRAModel {

    /// Models can implement this is they need a custom `MessageGenerator`.
    ///
    /// The default implementation returns `DefaultMessageGenerator`.
    func messageGenerator(tokenizer: Tokenizer) -> MessageGenerator
}

extension LLMModel {

    /// Default prepare step for ``LLMModel``.
    ///
    /// This will evaluate the prompt in chunks until there is a small number of
    /// tokens left to feed into the `TokenIterator`.
    public func prepare(_ input: LMInput, cache: [KVCache], windowSize: Int?) throws
        -> PrepareResult
    {
        let prefillStepSize = windowSize ?? 512
        var y = input.text

        // Prepare the prompt in chunks if larger than the prefill size
        while y.tokens.size > prefillStepSize {
            let input = y[.newAxis, ..<prefillStepSize]
            _ = self(input, cache: cache.isEmpty ? nil : cache, state: nil)
            // Only eval the cache - don't eval logits during prefill chunks.
            // Logits are [1, 512, 248320] = ~500MB and are not needed during prefill.
            // The per-layer eval in the model's forward pass handles freeing intermediates.
            eval(cache)
            Memory.clearCache()
            y = y[prefillStepSize...]
        }

        return .tokens(y)
    }

    public func messageGenerator(tokenizer: Tokenizer) -> MessageGenerator {
        DefaultMessageGenerator()
    }
}
