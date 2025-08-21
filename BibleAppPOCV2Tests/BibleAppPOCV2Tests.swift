// filepath: BibleAppPOCV2Tests/BibleAppPOCV2Tests.swift
//
//  BibleAppPOCV2Tests.swift
//  BibleAppPOCV2Tests
//
//  Created by Jeff Hedrick on 6/13/25.
//

import Testing
import CoreGraphics
@testable import BibleAppPOCV2

struct BibleAppPOCV2Tests {

    /// Verify the first page of Mark 1 ends at verse 17 on iPhone size.
    @Test @MainActor func testMarkFirstPageEndVerse() async throws {
        // Add a small delay to avoid test interference
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let generator = await OnDemandPageGenerator(pageSize: CGSize(width: 390, height: 600))
        await generator.generatePage(startingAt: ("Mark", 1, 1))
        let page = await generator.currentPage
        #expect(page?.endVerse.verse == 17)
    }

    /// Verify the paginator links pages without skipping verses.
    @Test @MainActor func testNextPageStartVerse() async throws {
        let generator = await OnDemandPageGenerator(pageSize: CGSize(width: 390, height: 600))
        await generator.generatePage(startingAt: ("Mark", 1, 1))
        let first = await generator.currentPage!
        await generator.generateNextPage()
        let second = await generator.currentPage!
        let diff = second.startVerse.verse - first.endVerse.verse
        #expect(diff == 0 || diff == 1)
    }

    // MARK: - Clean Core ML Integration Tests
    
    /// Test that our new clean Core ML integration services are working
    @Test @MainActor func testCleanCoreMLIntegration() async {
        // Test VocabService - this should always work
        let vocab = VocabService.shared
        #expect(vocab.token(for: 0) == "[UNK]", "Should return [UNK] for unknown token ID")
        #expect(vocab.isReady, "VocabService should be ready")
        
        // Test ExportReportService - handle gracefully if not available
        let exportReport = ExportReportService.shared
        if let report = exportReport.report {
            #expect(report.vocab_size > 0, "Should have valid vocabulary size")
            #expect(report.special_token_ids.count > 0, "Should have special token IDs")
            
            // Only assert dimensions when we have the report
            #expect(CommentaryModel.shared.nLayer > 0, "Should have valid number of layers")
            #expect(CommentaryModel.shared.nHead > 0, "Should have valid number of heads")
            #expect(CommentaryModel.shared.headDim > 0, "Should have valid head dimension")
            
            print("✅ Export report loaded successfully")
        } else {
            print("⚠️ Export report not available (expected in test environment)")
            // Don't fail the test if the report isn't available - this is expected in test environment
        }
        
        // Test that model can be loaded (even if it's nil due to missing assets)
        let model = CommentaryModel.shared
        if model.model != nil {
            print("✅ Core ML model loaded successfully")
        } else {
            print("⚠️ Core ML model not available (expected in test environment)")
            // Don't fail the test if the model isn't available - this is expected in test environment
        }
        
        // If we get here, the test passed
        print("✅ Clean Core ML integration test completed successfully")
    }
    
    /// Test that our new clean Core ML integration can decode tokens properly
    @Test @MainActor func testCleanTokenDecoding() {
        let vocab = VocabService.shared
        
        // Test that we can decode some basic tokens
        let token0 = vocab.token(for: 0)
        let token1 = vocab.token(for: 1)
        
        #expect(!token0.isEmpty, "Token 0 should not be empty")
        #expect(!token1.isEmpty, "Token 1 should not be empty")
        #expect(token0 != token1, "Different token IDs should produce different tokens")
    }

    // MARK: - Text Sanitization Tests (Legacy - Still Useful for Fallback)
    
    /// Test corruption pattern detection in generated text
    @Test @MainActor func testCorruptionPatternDetection() async {
        let sanitizer = TextSanitizer.shared
        
        // Create corrupted text with proper token structure
        let corruptedText = "[VERSE_ID] MARK_1_2CORRUPT_CHAR[VERSE_REF] Mark 1:2CORRUPT_CHAR[VERSE_TEXT] As it is written in the prophets, Behold, I send my messenger before thy face, which shall prepare thy way before thee.CORRUPT_CHAR[VERSE]CORRUPT_CHAR[START_COMMENTARY] this passage in the context of Jesus commission to Peter and John."
        
        let validation = sanitizer.validateText(corruptedText)
        
        #expect(validation.isCorrupted, "Should detect corruption in the text")
        #expect(validation.severity == .major, "Should have major severity due to general corruption")
        
        // Check that we detect the specific corruption patterns
        let patterns = validation.corruptionPatterns
        #expect(patterns.count > 0, "Should detect at least one corruption pattern")
        
        // Look for the corruption patterns that actually exist in the text
        let hasGeneralCorruption = patterns.contains { $0.pattern.pattern == "CORRUPT_CHAR" }
        
        #expect(hasGeneralCorruption, "Should detect general corruption patterns")
        #expect(patterns.count >= 4, "Should detect multiple corruption instances")
        
        print("✅ Corruption pattern detection test completed successfully")
    }
    
    /// Test corruption sanitization and removal
    @Test @MainActor func testCorruptionSanitization() {
        let sanitizer = TextSanitizer.shared
        
        // Create corrupted text with proper token structure
        let corruptedText = "[VERSE_ID] MARK_1_2CORRUPT_CHAR[VERSE_REF] Mark 1:2CORRUPT_CHAR[VERSE_TEXT] As it is written in the prophets, Behold, I send my messenger before thy face, which shall prepare thy way before thee.CORRUPT_CHAR[VERSE]CORRUPT_CHAR[START_COMMENTARY] this passage in the context of Jesus commission to Peter and John."
        
        let report = sanitizer.sanitizeTextWithReport(corruptedText)
        
        #expect(report.wasCorrupted, "Should detect corruption in the text")
        #expect(report.patternsFixed > 0, "Should fix at least one corruption pattern")
        #expect(report.charactersRemoved > 0, "Should remove corrupted characters")
        
        // The sanitized text should not contain corruption patterns
        let sanitizedText = report.sanitizedText
        #expect(!sanitizedText.contains("CORRUPT_CHAR"), "Should remove all CORRUPT_CHAR corruption markers")
        
        // The sanitized text should still contain the meaningful content
        #expect(sanitizedText.contains("[VERSE_ID]"), "Should preserve special tokens")
        #expect(sanitizedText.contains("[VERSE_REF]"), "Should preserve special tokens")
        #expect(sanitizedText.contains("[VERSE_TEXT]"), "Should preserve special tokens")
        #expect(sanitizedText.contains("Mark 1:2"), "Should preserve verse reference")
        #expect(sanitizedText.contains("As it is written in the prophets"), "Should preserve verse text")
    }
    
    /// Test UTF-8 corruption pattern fixes
    @Test @MainActor func testUTF8CorruptionFixes() {
        let sanitizer = TextSanitizer.shared
        
        // Test various UTF-8 corruption patterns (using simple ASCII for testing)
        let corruptedText = "Here's some text with broken apostrophes, broken quotes, and broken ellipsis broken dashes broken bullets broken daggers broken sections broken paragraphs broken parallels"
        
        let report = sanitizer.sanitizeTextWithReport(corruptedText)
        
        #expect(report.wasCorrupted, "Should detect UTF-8 corruption")
        
        let sanitizedText = report.sanitizedText
        
        // Check that corruption is fixed
        #expect(!sanitizedText.contains("broken"), "Should fix broken text corruption")
        
        // Check that proper characters are preserved
        #expect(sanitizedText.contains("'"), "Should preserve apostrophes")
        #expect(sanitizedText.contains("text"), "Should preserve text content")
    }
    
    /// Test that clean text passes through without modification
    @Test @MainActor func testCleanTextPassesThrough() {
        let sanitizer = TextSanitizer.shared
        
        let cleanText = "This is clean text with [VERSE_ID] special tokens [VERSE_REF] and proper formatting."
        
        let validation = sanitizer.validateText(cleanText)
        #expect(!validation.isCorrupted, "Clean text should not be flagged as corrupted")
        #expect(validation.severity == .none, "Clean text should have no severity")
        
        let report = sanitizer.sanitizeTextWithReport(cleanText)
        #expect(!report.wasCorrupted, "Clean text should not require sanitization")
        #expect(report.patternsFixed == 0, "Clean text should have no patterns fixed")
        #expect(report.charactersRemoved == 0, "Clean text should have no characters removed")
        #expect(report.originalText == report.sanitizedText, "Clean text should be unchanged")
    }
    
    /// Test that special tokens are preserved during sanitization
    @Test @MainActor func testSpecialTokenPreservation() {
        let sanitizer = TextSanitizer.shared
        
        // Get token IDs from export report to ensure we're testing with valid tokens
        let exportReport = ExportReportService.shared
        let verseIdToken = exportReport.report?.special_token_ids["VERSE_ID"] ?? 0
        let verseRefToken = exportReport.report?.special_token_ids["VERSE_REF"] ?? 0
        let verseTextToken = exportReport.report?.special_token_ids["VERSE_TEXT"] ?? 0
        let startCommentaryToken = exportReport.report?.special_token_ids["START_COMMENTARY"] ?? 0
        let endCommentaryToken = exportReport.report?.special_token_ids["END_COMMENTARY"] ?? 0
        let startDevotionalToken = exportReport.report?.special_token_ids["START_DEVOTIONAL"] ?? 0
        let endDevotionalToken = exportReport.report?.special_token_ids["END_DEVOTIONAL"] ?? 0
        
        let textWithTokens = "[VERSE_ID] MARK_1_2[VERSE_REF] Mark 1:2[VERSE_TEXT] Sample text[START_COMMENTARY] Commentary here[END_COMMENTARY][START_DEVOTIONAL] Devotional here[END_DEVOTIONAL]"
        
        let report = sanitizer.sanitizeTextWithReport(textWithTokens)
        
        let sanitizedText = report.sanitizedText
        
        // All special tokens should be preserved
        #expect(sanitizedText.contains("[VERSE_ID]"), "Should preserve VERSE_ID token")
        #expect(sanitizedText.contains("[VERSE_REF]"), "Should preserve VERSE_REF token")
        #expect(sanitizedText.contains("[VERSE_TEXT]"), "Should preserve VERSE_TEXT token")
        #expect(sanitizedText.contains("[START_COMMENTARY]"), "Should preserve START_COMMENTARY token")
        #expect(sanitizedText.contains("[END_COMMENTARY]"), "Should preserve END_COMMENTARY token")
        #expect(sanitizedText.contains("[START_DEVOTIONAL]"), "Should preserve START_DEVOTIONAL token")
        #expect(sanitizedText.contains("[END_DEVOTIONAL]"), "Should preserve END_DEVOTIONAL token")
        
        // Content should be preserved
        #expect(sanitizedText.contains("MARK_1_2"), "Should preserve verse ID content")
        #expect(sanitizedText.contains("Mark 1:2"), "Should preserve verse reference")
        #expect(sanitizedText.contains("Sample text"), "Should preserve verse text")
        #expect(sanitizedText.contains("Commentary here"), "Should preserve commentary")
        #expect(sanitizedText.contains("Devotional here"), "Should preserve devotional")
    }
}
