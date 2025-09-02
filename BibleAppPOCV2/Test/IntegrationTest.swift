// filepath: BibleAppPOCV2/Test/IntegrationTest.swift
import Foundation

// Simple integration test to verify semantic model works
class IntegrationTest {
    
    static func testSemanticIntegration() async {
        print("🧪 Testing Semantic Model Integration...")
        
        // Test 1: Initialize Bible commentary generator (on MainActor)
        let generator = await BibleCommentaryGenerator.shared
        print("✅ BibleCommentaryGenerator initialized")
        
        // Test 2: Generate commentary
        let testVerse = "In the beginning God created the heaven and the earth."
        let result = await generator.generateCommentary(for: "Genesis 1:1", verseText: testVerse)
        
        print("✅ Generated commentary: \(result.prefix(100))...")
        print("🎉 Integration test completed successfully!")
    }
    
    static func testCoreMLGenerator() async {
        print("🧪 Testing CoreML BibleCommentaryGenerator...")

        do {
            let generator = await BibleCommentaryGenerator.shared
            // Wait for the generator to be ready (it's already initialized in init)
            while !(await MainActor.run { generator.isReady }) {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            print("✅ BibleCommentaryGenerator ready")

            let testVerse = "For God so loved the world, that he gave his only begotten Son."
            let result = await generator.generateCommentary(for: "John 3:16", verseText: testVerse)

            print("✅ Generated commentary: \(result.prefix(100))...")

        } catch {
            print("❌ CoreML generator test failed: \(error)")
        }
    }
} 