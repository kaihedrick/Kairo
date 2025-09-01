// filepath: BibleAppPOCV2/ViewModels/VerseSummaryViewModel.swift

import Foundation

@MainActor
class VerseSummaryViewModel: ObservableObject {
    static let shared = VerseSummaryViewModel()
    
    @Published var commentaryText: String = ""
    @Published var devotionalText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var modelVersion: String = "GPT-2 Bible Commentary Model"
    @Published var modelAvailable: Bool = false
    
    private var bibleCommentaryGenerator: BibleCommentaryGenerator?
    private var pendingVerse: String?

    init() {
        attachModelReadyObserver()
        modelAvailable = (GenerationRuntime.shared.mode == .coreml)
        Task { await initializeGenerators() }
    }
    
    @MainActor
    private func attachModelReadyObserver() {
        NotificationCenter.default.addObserver(forName: .coreMLBibleModelReady, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.modelAvailable = true
                print("🟢 UI: Core ML modelAvailable = true")
                
                // Clear any loading errors when Core ML becomes ready
                if self?.errorMessage == "Core ML model is loading..." {
                    self?.errorMessage = ""
                }
                
                // If we have a pending verse, retry now that Core ML is ready
                if let pendingVerse = self?.pendingVerse {
                    print("🔄 Auto-retrying pending verse: \(pendingVerse)")
                    self?.summarize(verse: pendingVerse)
                    self?.pendingVerse = nil
                }
            }
        }
    }

    @MainActor
    private func initializeGenerators() async {
        // Initialize the GPT-2 Bible commentary generator
        bibleCommentaryGenerator = BibleCommentaryGenerator.shared
        print("✅ BibleCommentaryGenerator initialized successfully")
    }

    // Accepts a verse string, runs through GPT-2 commentary generator pipeline, and updates commentary and devotional
    func summarize(verse: String) {
        guard let commentaryGenerator = bibleCommentaryGenerator else {
            // Store pending verse to retry when Core ML becomes ready
            pendingVerse = verse
            errorMessage = "Core ML model is loading..."
            print("⚠️ Generator not ready yet, waiting for Core ML to load...")
            return
        }
        
        // Check if the Core ML model is ready before proceeding
        guard commentaryGenerator.isReady else {
            // Store pending verse to retry when Core ML becomes ready
            pendingVerse = verse
            errorMessage = "Core ML model is loading..."
            print("⚠️ Core ML model not ready yet, waiting for initialization...")
            return
        }
        
        print("🚀 calling generateCommentary with modelAvailable=\(modelAvailable), textLen=\(verse.count)")
        print("🚀 run(): modelAvailable=\(modelAvailable), vm id:", ObjectIdentifier(self))
        isLoading = true
        errorMessage = ""
        commentaryText = ""
        devotionalText = ""
        modelVersion = "GPT-2 Bible Commentary Model"
        
        // Run on background thread to avoid blocking UI
        Task {
            do {
                // Wait for generator to be ready (this prevents race conditions)
                while !commentaryGenerator.isReady {
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
                
                // Try GPT-2 commentary generator first
                // Parse the verse to extract reference and text properly
                let (verseRef, verseText) = parseVerse(verse)
                
                // Use the new parser to get structured commentary and devotional
                let parsedContent = await commentaryGenerator.generateCommentaryAndDevotional(for: verseRef, verseText: verseText)
            
            await MainActor.run {
                self.isLoading = false
                
                // Use the parsed sections directly
                self.commentaryText = parsedContent.commentary
                self.devotionalText = parsedContent.devotional
                
                if parsedContent.commentary.isEmpty && parsedContent.devotional.isEmpty {
                    // Only try fallback summarizer if we're in fallback mode
                    if GenerationRuntime.shared.mode == .fallback {
                        self.tryFallbackSummarizer(verse: verse)
                    } else {
                        self.errorMessage = "No content generated from Core ML model"
                    }
                } else {
                    self.errorMessage = ""
                }
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Generation failed: \(error.localizedDescription)"
            }
        }
        }
    }
    
    // Fallback to improved summarizer if GPT-2 fails
    private func tryFallbackSummarizer(verse: String) {
        // Only use fallback summarizer when in fallback mode
        guard GenerationRuntime.shared.mode == .fallback else {
            errorMessage = "Fallback summarizer not available in Core ML mode"
            return
        }
        
        // Note: improvedSummarizer is not currently implemented
        // Fallback to simple static response for now
        commentaryText = "Fallback commentary not currently available. Please ensure Core ML model is loaded."
        devotionalText = "Fallback devotional not currently available. Please ensure Core ML model is loaded."
        errorMessage = "Fallback summarizer not implemented"
        return
        

    }
    
    // Parse structured output to extract commentary and devotional sections
    private func parseStructuredOutput(_ text: String) -> (commentary: String, devotional: String) {
        func slice(_ s: String, _ a: String, _ b: String) -> String {
            guard let r1 = s.range(of: a), let r2 = s.range(of: b), r1.upperBound <= r2.lowerBound else { return "" }
            return String(s[r1.upperBound..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let commentary = slice(text, "[START_COMMENTARY]", "[END_COMMENTARY]")
        let devotional = slice(text, "[START_DEVOTIONAL]", "[END_DEVOTIONAL]")
        return (commentary, devotional)
    }
    
    // Clear the current summary
    func clearSummary() {
        commentaryText = ""
        devotionalText = ""
        errorMessage = ""
    }
    
    /// Parse a verse string to extract the reference and text
    /// Handles formats like "Matthew 1:1 In the beginning..." or "6 1 Take heed..."
    private func parseVerse(_ verse: String) -> (verseRef: String, verseText: String) {
        // First, try to find a verse reference pattern like "Book Chapter:Verse"
        let versePattern = #"^([A-Za-z]+)\s+(\d+):(\d+)\s+(.+)$"#
        
        if let regex = try? NSRegularExpression(pattern: versePattern, options: []),
           let match = regex.firstMatch(in: verse, options: [], range: NSRange(verse.startIndex..., in: verse)) {
            
            let book = String(verse[Range(match.range(at: 1), in: verse)!])
            let chapter = String(verse[Range(match.range(at: 2), in: verse)!])
            let verseNum = String(verse[Range(match.range(at: 3), in: verse)!])
            let text = String(verse[Range(match.range(at: 4), in: verse)!])
            
            let verseRef = "\(book) \(chapter):\(verseNum)"
            return (verseRef, text)
        }
        
        // If that doesn't work, try to find a pattern like "Chapter Verse Text"
        let chapterVersePattern = #"^(\d+)\s+(\d+)\s+(.+)$"#
        
        if let regex = try? NSRegularExpression(pattern: chapterVersePattern, options: []),
           let match = regex.firstMatch(in: verse, options: [], range: NSRange(verse.startIndex..., in: verse)) {
            
            let chapter = String(verse[Range(match.range(at: 1), in: verse)!])
            let verseNum = String(verse[Range(match.range(at: 2), in: verse)!])
            let text = String(verse[Range(match.range(at: 3), in: verse)!])
            
            // Try to infer the book from context or use a default
            let verseRef = "Chapter \(chapter):\(verseNum)"
            return (verseRef, text)
        }
        
        // If all else fails, use the simple approach but limit the verse reference
        let components = verse.components(separatedBy: " ")
        if components.count >= 3 {
            // Look for a pattern like "Book Chapter:Verse" or "Chapter Verse"
            let firstTwo = "\(components[0]) \(components[1])"
            
            // Check if the second component contains a colon (indicating verse reference)
            if components[1].contains(":") {
                let verseRef = firstTwo
                let verseText = components.dropFirst(2).joined(separator: " ")
                return (verseRef, verseText)
            } else if components.count >= 3 && components[2].contains(":") {
                // Pattern like "Book Chapter Verse:Number"
                let verseRef = "\(components[0]) \(components[1]):\(components[2].split(separator: ":")[1])"
                let verseText = components.dropFirst(3).joined(separator: " ")
                return (verseRef, verseText)
            } else {
                // Simple case: take first two words as reference
                let verseRef = firstTwo
                let verseText = components.dropFirst(2).joined(separator: " ")
                return (verseRef, verseText)
            }
        }
        
        // Fallback: return the whole string as text
        return ("Unknown", verse)
    }
    
    // Get the status of the generators
    func getSummarizerStatus() -> String {
        if let commentaryGenerator = bibleCommentaryGenerator, commentaryGenerator.isReady {
            return "GPT-2 Bible Commentary Model Ready"
        } else if bibleCommentaryGenerator != nil {
            return "GPT-2 Bible Commentary Model Loading..."
        } else if GenerationRuntime.shared.mode == .fallback {
            return "Fallback Mode (Improved Bible AI Model Not Implemented)"
        } else {
            return "No models available"
        }
    }
    
    // Check if the generators are ready
    func isSummarizerReady() -> Bool {
        if let commentaryGenerator = bibleCommentaryGenerator {
            return commentaryGenerator.isReady
        } else if GenerationRuntime.shared.mode == .fallback {
            return false  // improvedSummarizer is not implemented
        }
        return false
    }
    
    // Get detailed status information for debugging
    func getDetailedStatus() -> String {
        var status = "GenerationRuntime Mode: \(GenerationRuntime.shared.mode)\n"
        status += "Model Available: \(modelAvailable)\n"
        
        if let commentaryGenerator = bibleCommentaryGenerator {
            status += "BibleCommentaryGenerator: \(commentaryGenerator.isReady ? "Ready" : "Loading")\n"
        } else {
            status += "BibleCommentaryGenerator: Not Initialized\n"
        }
        
        status += "ImprovedBibleSummarizer: Not Implemented\n"
        
        return status
    }
    
    // Retry initialization
    func retryInitialization() {
        errorMessage = ""
        Task { await initializeGenerators() }
    }
}
