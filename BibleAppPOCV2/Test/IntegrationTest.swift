// filepath: BibleAppPOCV2/Test/IntegrationTest.swift
import Foundation

// Simple integration test to verify semantic model works
class IntegrationTest {
    
    static func testSemanticIntegration() async {
        print("🧪 Testing Semantic Model Integration...")
        
        // Test 1: Initialize improved summarizer on MainActor
        let summarizer = await MainActor.run { ImprovedBibleSummarizer() }
        print("✅ ImprovedBibleSummarizer initialized")
        
        // Test 2: Generate commentary
        let testVerse = "In the beginning God created the heaven and the earth."
        let result = await summarizer.generateCommentary(for: testVerse)
        
        print("✅ Generated commentary: \(result.prefix(100))...")
        print("🎉 Integration test completed successfully!")
    }
    
    static func testSemanticGenerator() async {
        print("🧪 Testing SemanticBibleGenerator directly...")
        
        do {
            let generator = try SemanticBibleGenerator()
            print("✅ SemanticBibleGenerator initialized successfully")
            
            let testVerse = "For God so loved the world, that he gave his only begotten Son."
            let result = try await generator.generateCommentary(for: testVerse)
            
            print("✅ Generated commentary: \(result.prefix(100))...")
            
        } catch {
            print("❌ SemanticBibleGenerator test failed: \(error)")
        }
    }
} 