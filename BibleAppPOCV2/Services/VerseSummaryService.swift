import Foundation

protocol VerseSummaryServiceProtocol {
    func fetchSummary(for verse: VerseKey, text: String) async throws -> String
}

/// Service that integrates summarization using existing LLM infrastructure
@MainActor
class VerseSummaryService: VerseSummaryServiceProtocol, ObservableObject {
    // MARK: - Services
    private let llmService = LLMService()
    private let tokenizer = T5Tokenizer()
    
    // MARK: - Published Properties
    @Published var isLoading = false
    @Published var lastError: String?
    
    init() {}
    
    // MARK: - Protocol Implementation
    func fetchSummary(for verse: VerseKey, text: String) async throws -> String {
        isLoading = true
        lastError = nil
        
        defer {
            isLoading = false
        }
        
        // Use existing LLM infrastructure for summary generation
        let tokens = tokenizer.tokenize(text)
        let encoderOutputs = llmService.encode(tokens: tokens)
        
        // Simple decoder simulation (same as VerseSummaryViewModel)
        let summaryTokenIDs = encoderOutputs.map { Int($0) }.reversed()
        let summaryText = detokenize(tokenIDs: Array(summaryTokenIDs))
        
        return summaryText
    }
    
    // MARK: - Helper Methods
    
    /// Detokenize token IDs to text using tokenizer's vocab
    private func detokenize(tokenIDs: [Int]) -> String {
        // Reverse vocab lookup: token ID → token string
        let idToToken = tokenizer.vocab.reduce(into: [Int: String]()) { dict, pair in dict[pair.value] = pair.key }
        let tokens = tokenIDs.compactMap { idToToken[$0] }
        return tokens.joined(separator: " ")
    }
    
    /// Check if service is ready
    var isReady: Bool {
        return true // LLMService and T5Tokenizer are always ready
    }
    
    /// Get service status
    var statusMessage: String {
        if isLoading {
            return "Generating summary..."
        }
        
        if let error = lastError {
            return "Error: \(error)"
        }
        
        return "Ready to generate verse summaries"
    }
}
