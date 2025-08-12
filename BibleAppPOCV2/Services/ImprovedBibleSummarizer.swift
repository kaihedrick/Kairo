// filepath: BibleAppPOCV2/Services/ImprovedBibleSummarizer.swift
import Foundation
import CoreML

// MARK: - Improved Bible Summarizer
@MainActor
class ImprovedBibleSummarizer {
    private var model: MLModel?
    private let tokenizer = GPT2BPEEncoder.shared
    private var commentaryGenerator: BibleCommentaryGenerator?
    private var didInit = false
    
    init() {
        // Try to initialize the Bible commentary model
        self.commentaryGenerator = BibleCommentaryGenerator.shared
        
        // Initialize the original model as fallback only if requested
        if GenerationRuntime.shared.mode == .fallback {
            initializeModel()
        } else {
            print("ℹ️ Skipping fallback ImprovedBibleSummarizer init: Core ML is active")
        }
    }
    
    func generateCommentary(for verse: String) async -> String {
        // Try Bible commentary generator first (new model)
        if let commentaryGen = commentaryGenerator {
            // Parse the verse to extract reference and text properly
            let (verseRef, verseText) = parseVerse(verse)
            
            let commentaryResult = await commentaryGen.generateCommentary(for: verseRef, verseText: verseText)
            if !commentaryResult.isEmpty && !commentaryResult.contains("Unable to generate commentary") {
                return commentaryResult
            }
        }
        
        // No semantic generator available - continue to fallback
        
        // Fallback to basic commentary
        return "This verse teaches us about God's love and guidance."
    }
    
    func generateDevotional(for verse: String) async -> String {
        // Try Bible commentary generator first (new model)
        if let commentaryGen = commentaryGenerator {
            // Parse the verse to extract reference and text properly
            let (verseRef, verseText) = parseVerse(verse)
            
            let commentaryResult = await commentaryGen.generateCommentary(for: verseRef, verseText: verseText)
            if !commentaryResult.isEmpty && !commentaryResult.contains("Unable to generate devotional") {
                // Don't return the commentary string as devotional - let parseStructuredOutput handle it
                return ""
            }
        }
        
        // Fallback to basic devotional
        return "This verse reminds us of God's love and guidance in our daily lives."
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
        
        // Fallback: try to find any pattern with numbers and colons
        let fallbackPattern = #"^([A-Za-z\s]+)(\d+):(\d+)\s+(.+)$"#
        
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: []),
           let match = regex.firstMatch(in: verse, options: [], range: NSRange(verse.startIndex..., in: verse)) {
            
            let book = String(verse[Range(match.range(at: 1), in: verse)!]).trimmingCharacters(in: .whitespaces)
            let chapter = String(verse[Range(match.range(at: 2), in: verse)!])
            let verseNum = String(verse[Range(match.range(at: 3), in: verse)!])
            let text = String(verse[Range(match.range(at: 4), in: verse)!])
            
            let verseRef = "\(book) \(chapter):\(verseNum)"
            return (verseRef, text)
        }
        
        // If no pattern matches, return the whole string as text with a generic reference
        return ("Unknown Reference", verse)
    }
    
    // MARK: - Fallback Model (only used when Core ML is not available)
    
    private func initializeModel() {
        // This is only called when GenerationRuntime.shared.mode == .fallback
        // Load a basic fallback model if needed
        print("⚠️ Initializing fallback model - Core ML should be preferred")
    }
}
