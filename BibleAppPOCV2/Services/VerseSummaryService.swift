import Foundation
import BibleAppPOCV2
import BibleAppPOCV2.Services.BibleVerseCommentaryGenerator // If this is the correct path

protocol VerseSummaryServiceProtocol {
    func fetchSummary(for verse: VerseKey) async throws -> String
}

/// Service that integrates both summarization and commentary generation
@MainActor
class VerseSummaryService: VerseSummaryServiceProtocol, ObservableObject {
    // MARK: - Services
    private let llmService = LLMService() // Direct instantiation, no singleton
    private let commentaryGenerator = BibleVerseCommentaryGenerator()
    
    // MARK: - Published Properties
    @Published var isLoading = false
    @Published var lastError: String?
    
    init() {}
    
    // MARK: - Protocol Implementation
    func fetchSummary(for verse: VerseKey) async throws -> String {
        // TODO: Implement summary generation using available model or service
        // Placeholder: Return empty summary for migration
        return ""
    }
    
    // MARK: - Enhanced Summary Generation
    
    /// Generate a comprehensive verse analysis including summary and commentary
    func generateVerseAnalysis(
        verseKey: VerseKey,
        text: String,
        includeCommentary: Bool = true
    ) async -> VerseAnalysis? {
        
        isLoading = true
        lastError = nil
        
        defer {
            isLoading = false
        }
        
        do {
            // TODO: Implement summary generation using available model or service
            // Placeholder: Return empty summary for migration
            var biblical: String?
            var devotional: String?
            if includeCommentary {
                let reference = "\(verseKey.book) \(verseKey.chapter):\(verseKey.verse)"
                biblical = await commentaryGenerator.generateCommentary(
                    verseText: text,
                    verseReference: reference,
                    type: .biblical
                )
                devotional = await commentaryGenerator.generateCommentary(
                    verseText: text,
                    verseReference: reference,
                    type: .devotional
                )
            }
            return VerseAnalysis(
                verseKey: verseKey,
                originalText: text,
                summary: "",
                biblicalCommentary: biblical,
                devotionalInsight: devotional
            )
            
        } catch {
            lastError = error.localizedDescription
            print("❌ Error generating verse analysis: \(error)")
            return nil
        }
    }
    
    /// Generate commentary only (faster for UI interactions)
    func generateCommentaryOnly(
        verseKey: VerseKey,
        text: String,
        type: BibleVerseCommentaryGenerator.CommentaryType = .devotional
    ) async -> String? {
        
        let reference = "\(verseKey.book) \(verseKey.chapter):\(verseKey.verse)"
        
        return await commentaryGenerator.generateCommentary(
            verseText: text,
            verseReference: reference,
            type: type
        )
    }
    
    /// Check if both services are ready
    var isReady: Bool {
        return commentaryGenerator.isModelLoaded
    }
    
    /// Get service status
    var statusMessage: String {
        if isLoading {
            return "Generating analysis..."
        }
        
        if !commentaryGenerator.isModelLoaded {
            return "Loading commentary model..."
        }
        
        if let error = lastError {
            return "Error: \(error)"
        }
        
        return "Ready to generate verse analysis"
    }
}

// MARK: - Data Models

struct VerseAnalysis {
    let verseKey: VerseKey
    let originalText: String
    let summary: VerseSummary
    let biblicalCommentary: String?
    let devotionalInsight: String?
    
    var hasCommentary: Bool {
        return biblicalCommentary != nil || devotionalInsight != nil
    }
}

// MARK: - Integration with Bible Reader

extension VerseSummaryService {
    
    /// Generate analysis for the current page's verses
    func analyzePageVerses(_ pageSlice: OptimizedPageSlice) async -> [VerseAnalysis] {
        var analyses: [VerseAnalysis] = []
        
        for verseKey in pageSlice.verseKeys {
            // Extract verse text from the data loader
            if let verseText = await getVerseText(for: verseKey) {
                if let analysis = await generateVerseAnalysis(
                    verseKey: verseKey,
                    text: verseText,
                    includeCommentary: true
                ) {
                    analyses.append(analysis)
                }
            }
        }
        
        return analyses
    }
    
    private func getVerseText(for verseKey: VerseKey) async -> String? {
        let loader = OptimizedBibleDataLoader()
        
        guard let chapter = await loader.loadChapterContent(book: verseKey.book, chapter: verseKey.chapter),
              let verseContent = chapter.verses.first(where: { $0.verse == verseKey.verse }) else {
            return nil
        }
        
        return verseContent.text
    }
}
