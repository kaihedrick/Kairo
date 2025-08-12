// File: BibleAppPOCV2/ViewModels/VerseSummaryViewModel.swift
// Directory: ViewModels
// Purpose: Use BibleCommentaryGenerator (GPT-2) for structured commentary and devotional generation

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
    private var improvedSummarizer: ImprovedBibleSummarizer?
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
                // If we have a pending verse, retry now that Core ML is ready
                if let pendingVerse = self?.pendingVerse {
                    self?.summarize(verse: pendingVerse)
                    self?.pendingVerse = nil
                }
            }
        }
    }

    @MainActor
    private func initializeGenerators() async {
        // Initialize the new GPT-2 Bible commentary generator first
        bibleCommentaryGenerator = BibleCommentaryGenerator.shared
        print("✅ BibleCommentaryGenerator initialized successfully")
        
        // Initialize the improved summarizer only if Core ML is not active
        if GenerationRuntime.shared.mode == .fallback {
            improvedSummarizer = ImprovedBibleSummarizer()
            print("✅ ImprovedBibleSummarizer initialized as fallback")
        } else {
            print("ℹ️ Skipping fallback init: Core ML is active")
        }
    }

    // Accepts a verse string, runs through GPT-2 commentary generator pipeline, and updates commentary and devotional
    func summarize(verse: String) {
        guard let commentaryGenerator = bibleCommentaryGenerator else {
            // Store pending verse to retry when Core ML becomes ready
            pendingVerse = verse
            print("⚠️ Generator not ready yet, waiting for Core ML to load...")
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
            // Try GPT-2 commentary generator first
            // Parse the verse to extract reference and text properly
            let (verseRef, verseText) = parseVerse(verse)
            
            let commentaryResult = await commentaryGenerator.generateCommentary(for: verseRef, verseText: verseText)
            
            // For devotional, we'll use the same commentary for now
            let devotionalResult = commentaryResult
            
            await MainActor.run {
                self.isLoading = false
                
                // Parse the results to extract commentary and devotional
                let (commentary, devotional) = self.parseStructuredOutput(commentaryResult, devotional: devotionalResult)
                
                self.commentaryText = commentary
                self.devotionalText = devotional
                
                if commentary.isEmpty && devotional.isEmpty {
                    // Try fallback to improved summarizer
                    self.tryFallbackSummarizer(verse: verse)
                } else {
                    self.errorMessage = ""
                }
            }
        }
    }
    
    // Fallback to improved summarizer if GPT-2 fails
    private func tryFallbackSummarizer(verse: String) {
        guard let summarizer = improvedSummarizer else {
            errorMessage = "No AI models available"
            return
        }
        
        Task {
            let result = await summarizer.generateCommentary(for: verse)
            
            await MainActor.run {
                let (commentary, devotional) = self.parseStructuredOutput(result, devotional: "")
                
                if !commentary.isEmpty || !devotional.isEmpty {
                    self.commentaryText = commentary
                    self.devotionalText = devotional
                    self.modelVersion = "Improved Bible AI Model (Fallback)"
                    self.errorMessage = ""
                } else {
                    self.errorMessage = "No content generated from any model"
                }
            }
        }
    }
    
    // Parse structured output to extract commentary and devotional sections
    private func parseStructuredOutput(_ commentaryText: String, devotional: String = "") -> (commentary: String, devotional: String) {
        var commentary = ""
        var devotionalText = devotional
        
        // Extract commentary from structured output
        if let startRange = commentaryText.range(of: "[START_COMMENTARY]"),
           let endRange = commentaryText.range(of: "[END_COMMENTARY]") {
            let startIndex = commentaryText.index(startRange.upperBound, offsetBy: 0)
            commentary = String(commentaryText[startIndex..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // If no structured tokens found, treat the whole text as commentary
            commentary = commentaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Extract devotional from structured output
        if let startRange = devotionalText.range(of: "[START_DEVOTIONAL]"),
           let endRange = devotionalText.range(of: "[END_DEVOTIONAL]") {
            let startIndex = devotionalText.index(startRange.upperBound, offsetBy: 0)
            devotionalText = String(devotionalText[startIndex..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if devotionalText.isEmpty {
            // If no devotional text provided, try to extract from commentary text
            if let startRange = commentaryText.range(of: "[START_DEVOTIONAL]"),
               let endRange = commentaryText.range(of: "[END_DEVOTIONAL]") {
                let startIndex = commentaryText.index(startRange.upperBound, offsetBy: 0)
                devotionalText = String(commentaryText[startIndex..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return (commentary, devotionalText)
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
        if bibleCommentaryGenerator != nil {
            return "GPT-2 Bible Commentary Model Ready"
        } else if improvedSummarizer != nil {
            return "Improved Bible AI Model Ready (Fallback)"
        } else {
            return "No models available"
        }
    }
    
    // Check if the generators are ready
    func isSummarizerReady() -> Bool {
        return bibleCommentaryGenerator != nil || improvedSummarizer != nil
    }
    
    // Retry initialization
    func retryInitialization() {
        errorMessage = ""
        Task { await initializeGenerators() }
    }
}
