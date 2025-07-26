// File: BibleAppPOCV2/ViewModels/VerseSummaryViewModel.swift
// Directory: ViewModels
// Purpose: Simulate decoder outputs and detokenize results for verse summarization

import Foundation

class VerseSummaryViewModel: ObservableObject {
    @Published var summaryText: String = ""
    private let tokenizer = T5Tokenizer()
    private let llmService = LLMService()

    // Accepts a verse string, runs through pipeline, and updates summaryText
    func summarize(verse: String) {
        let tokens = tokenizer.tokenize(verse)
        let encoderOutputs = llmService.encode(tokens: tokens)
        // --- Decoder Simulation ---
        // For demonstration, simulate decoder output as reversed encoder outputs mapped to token IDs
        let summaryTokenIDs = encoderOutputs.map { Int($0) }.reversed()
        // --- Detokenization ---
        let summaryText = detokenize(tokenIDs: Array(summaryTokenIDs))
        self.summaryText = summaryText
    }

    // Detokenize token IDs to text using tokenizer's vocab
    private func detokenize(tokenIDs: [Int]) -> String {
        // Reverse vocab lookup: token ID → token string
        let idToToken = tokenizer.vocab.reduce(into: [Int: String]()) { dict, pair in dict[pair.value] = pair.key }
        let tokens = tokenIDs.compactMap { idToToken[$0] }
        return tokens.joined(separator: " ")
    }
}
