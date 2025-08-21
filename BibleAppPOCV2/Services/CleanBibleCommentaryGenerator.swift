// filepath: BibleAppPOCV2/Services/CleanBibleCommentaryGenerator.swift
import Foundation
import CoreML
import SwiftUI

/// Clean Bible commentary generation using the new Core ML integration.
/// Generates clean text from the model and applies formatting after generation.
/// No text sanitization needed - trust the clean exported data.
@MainActor
final class CleanBibleCommentaryGenerator: ObservableObject {
    static let shared = CleanBibleCommentaryGenerator()
    
    // Lazy initialization to avoid creating Generator during test suite setup
    private lazy var lazyGenerator: Generator = {
        return Generator()
    }()
    
    @Published var isGenerating = false
    @Published var generatedText = ""
    @Published var error: String?
    @Published private(set) var isReady = false
    
    // Generator is now lazy to avoid initialization during test suite setup
    private let exportReport = ExportReportService.shared
    private let vocab = VocabService.shared
    
    private init() {
        // Check if all required services are ready
        isReady = vocab.isReady &&
                  (exportReport.report?.special_token_ids.count ?? 0) > 0
        
        if isReady {
            print("✅ CleanBibleCommentaryGenerator ready with vocabulary tokens")
        } else {
            print("⚠️ CleanBibleCommentaryGenerator not ready - some services unavailable")
        }
    }
    
    /// Generate commentary and devotional for a given verse
    func generateCommentaryAndDevotional(
        for verse: String,
        book: String,
        chapter: Int,
        verseNumber: Int
    ) async {
        guard isReady else {
            error = "Generator not ready - check Core ML model and vocabulary"
            return
        }
        
        isGenerating = true
        error = nil
        
        do {
            // Create prompt with special tokens
            let prompt = createPrompt(
                verse: verse,
                book: book,
                chapter: chapter,
                verseNumber: verseNumber
            )
            
            // Generate text using the model
            let rawText = try await generateText(prompt: prompt)
            
            // Apply formatting to clean text (no sanitization needed)
            let formattedText = formatGeneratedText(rawText)
            
            generatedText = formattedText
            
        } catch {
            self.error = "Generation failed: \(error.localizedDescription)"
            print("❌ Generation error: \(error)")
        }
        
        isGenerating = false
    }
    
    private func createPrompt(
        verse: String,
        book: String,
        chapter: Int,
        verseNumber: Int
    ) -> [Int] {
        var promptIds: [Int] = []
        
        // Add verse ID token
        let verseId = exportReport.id(for: .VERSE_ID)
        if verseId > 0 {
            promptIds.append(verseId)
        }
        
        // Add verse reference token
        let verseRefId = exportReport.id(for: .VERSE_REF)
        if verseRefId > 0 {
            promptIds.append(verseRefId)
        }
        
        // Add verse text token
        let verseTextId = exportReport.id(for: .VERSE_TEXT)
        if verseTextId > 0 {
            promptIds.append(verseTextId)
        }
        
        // Add verse tag token
        let verseTagId = exportReport.id(for: .VERSE)
        if verseTagId > 0 {
            promptIds.append(verseTagId)
        }
        
        // Add start commentary token
        let startCommentaryId = exportReport.id(for: .START_COMMENTARY)
        if startCommentaryId > 0 {
            promptIds.append(startCommentaryId)
        }
        
        return promptIds
    }
    
    private func generateText(prompt: [Int]) async throws -> String {
        var kv = lazyGenerator.createEmptyCaches()
        var generatedTokens: [Int] = []
        var lastId = prompt.last ?? 0
        
        // Generate tokens step by step
        for _ in 0..<100 { // Limit to prevent infinite generation
            let result = try lazyGenerator.step(promptIds: [lastId], kv: &kv)
            generatedTokens.append(result)
            lastId = result
            
            // Check for end token
            let endCommentaryId = exportReport.id(for: .END_COMMENTARY)
            if result == endCommentaryId {
                break
            }
        }
        
        // Decode tokens to text
        return generatedTokens.decodeToString()
    }
    
    private func formatGeneratedText(_ rawText: String) -> String {
        // Apply Crossway typography standards to clean text
        var formatted = rawText
        
        // Remove any remaining special tokens
        let specialTokens = Special.allCases.map { $0.rawValue }
        for token in specialTokens {
            formatted = formatted.replacingOccurrences(of: token, with: "")
        }
        
        // Apply basic formatting
        formatted = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure proper spacing
        formatted = formatted.replacingOccurrences(of: "  ", with: " ")
        
        return formatted
    }
}
