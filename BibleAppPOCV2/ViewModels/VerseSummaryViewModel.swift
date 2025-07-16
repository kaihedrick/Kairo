import Foundation
import Combine

@MainActor
class VerseSummaryViewModel: ObservableObject {
    @Published var summaryText: String = ""
    @Published var currentSummary: VerseSummary? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let service: VerseSummaryServiceProtocol
    private let llmService: LLMService
    private let cache: VerseSummaryCache
    private let bibleRepository: OptimizedBibleRepository

    init(service: VerseSummaryServiceProtocol = VerseSummaryService.shared,
         llmService: LLMService = LLMService.shared,
         cache: VerseSummaryCache = VerseSummaryCache.shared) {
        self.service = service
        self.llmService = llmService
        self.cache = cache
        self.bibleRepository = OptimizedBibleRepository()
    }

    /// Fetches the summary for a specific verse using the trained BibleSummarizer model
    func loadSummary(for verse: VerseKey) async {
        isLoading = true
        errorMessage = nil
        summaryText = ""
        currentSummary = nil

        // Check cache first
        if let cached = cache.getCachedSummary(for: verse) {
            summaryText = cached.summaryText
            currentSummary = cached
            isLoading = false
            return
        }

        do {
            // First, get the verse text (you'll need to implement this based on your data structure)
            let verseText = await getVerseText(for: verse)
            
            // Use the trained LLM model to generate summary
            let verseSummary = try await llmService.summarizeVerse(verseKey: verse, text: verseText)
            
            // Update UI
            summaryText = verseSummary.summaryText
            currentSummary = verseSummary
            
            // Cache the result
            cache.saveSummary(verseSummary)
            
        } catch {
            print("❌ LLM Summary Error: \(error)")
            print("🔄 Falling back to service-based summary...")
            
            // Fallback to service-based summary
            do {
                let summary = try await service.fetchSummary(for: verse)
                summaryText = summary
                
                // Create VerseSummary object and cache it
                let verseSummary = VerseSummary(
                    reference: "\(verse.book) \(verse.chapter):\(verse.verse)",
                    book: verse.book,
                    chapter: verse.chapter,
                    verse: verse.verse,
                    summaryText: summary
                )
                currentSummary = verseSummary
                cache.saveSummary(verseSummary)
                
            } catch {
                errorMessage = "Unable to generate AI summary for \(verse.book) \(verse.chapter):\(verse.verse). \(error.localizedDescription)"
                print("❌ Service Summary Error: \(error)")
            }
        }

        isLoading = false
    }
    
    /// Fallback method using the service layer (for compatibility)
    func loadSummaryUsingService(for verse: VerseKey) async {
        isLoading = true
        errorMessage = nil
        summaryText = ""
        currentSummary = nil

        // Check cache first
        if let cached = cache.getCachedSummary(for: verse) {
            summaryText = cached.summaryText
            currentSummary = cached
            isLoading = false
            return
        }

        do {
            let summary = try await service.fetchSummary(for: verse)
            summaryText = summary
            
            // Create VerseSummary object and cache it
            let verseSummary = VerseSummary(
                reference: "\(verse.book) \(verse.chapter):\(verse.verse)",
                book: verse.book,
                chapter: verse.chapter,
                verse: verse.verse,
                summaryText: summary
            )
            currentSummary = verseSummary
            cache.saveSummary(verseSummary)
        } catch {
            errorMessage = "Unable to generate summary for \(verse.book) \(verse.chapter):\(verse.verse)."
        }

        isLoading = false
    }
    
    /// Get verse text from your data source
    private func getVerseText(for verse: VerseKey) async -> String {
        do {
            let chapter = try await bibleRepository.loadChapter(book: verse.book, chapter: verse.chapter)
            if let foundVerse = chapter.verses.first(where: { $0.reference.verse == verse.verse }) {
                return foundVerse.text
            } else {
                print("⚠️ Verse not found: \(verse.book) \(verse.chapter):\(verse.verse)")
                return "Verse text not found for \(verse.book) \(verse.chapter):\(verse.verse)"
            }
        } catch {
            print("❌ Error loading verse text: \(error)")
            return "Error loading verse text for \(verse.book) \(verse.chapter):\(verse.verse)"
        }
    }

    func clear() {
        summaryText = ""
        currentSummary = nil
        errorMessage = nil
        isLoading = false
    }
}
