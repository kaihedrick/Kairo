import Foundation

protocol VerseSummaryServiceProtocol {
    func fetchSummary(for verse: VerseKey) async throws -> String
}

class VerseSummaryService: VerseSummaryServiceProtocol, ObservableObject {
    static let shared = VerseSummaryService()
    
    private init() {}
    
    func fetchSummary(for verse: VerseKey) async throws -> String {
        // Mock implementation for testing
        // In production, this would call an actual AI service
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        return "This is a mock AI summary for \(verse.book) \(verse.chapter):\(verse.verse). In a real implementation, this would contain an AI-generated summary of the verse content."
    }
}
