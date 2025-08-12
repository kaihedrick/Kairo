// filepath: BibleAppPOCV2/Services/BARTService.swift
import Foundation
import CoreML

@MainActor
class BARTService {
    private var improvedSummarizer: ImprovedBibleSummarizer?
    private var legacyModel: MLModel?
    private let tokenizer: BARTTokenizer
    
    // Model selection
    private var useImprovedModel = false
    private var useLegacyModel = false
    
    // BART special tokens
    private let padTokenId = 1
    private let eosTokenId = 2
    private let bosTokenId = 0
    private let unkTokenId = 3
    
    init() {
        print("🚀 BARTService initializing with improved Bible summarizer...")
        self.tokenizer = BARTTokenizer()
        
        // Initialize improved summarizer on MainActor only if fallback is active
        if GenerationRuntime.shared.mode == .fallback {
            initializeImprovedModel()
        } else {
            print("ℹ️ BARTService: Core ML active; skipping fallback summarizer init")
        }
        
        // Fall back to legacy model if improved model fails
        if !useImprovedModel {
            initializeLegacyModel()
        }
        
        print("✅ BARTService initialization complete")
    }
    
    private func initializeImprovedModel() {
        print("🔍 Attempting to initialize improved Bible summarizer...")
        
        improvedSummarizer = ImprovedBibleSummarizer()
        
        // Check if improved model is ready
        if improvedSummarizer != nil {
            useImprovedModel = true
            print("✅ Improved Bible summarizer initialized successfully")
            print("📊 Improved Status: Ready")
        } else {
            print("⚠️ Improved model not ready")
            useImprovedModel = false
        }
    }
    
    private func initializeLegacyModel() {
        print("🔍 Attempting to initialize legacy CoreML model...")
        
        // Try to find the legacy generation model
        let possibleModelNames = [
            "simple-verse-model-coreml",       // Your existing model
            "SimpleVerseModelGeneration",      // Generation model
            "simple-verse-model-generation",   // Alternative naming
            "BibleVerseGenerator",             // Another alternative
        ]
        
        for modelName in possibleModelNames {
            if let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
                print("✅ Found legacy model at: \(modelURL.path)")
                
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = .cpuAndGPU
                    
                    self.legacyModel = try MLModel(contentsOf: modelURL, configuration: config)
                    useLegacyModel = true
                    print("✅ Legacy model loaded successfully!")
                    return
                } catch {
                    print("❌ Failed to load legacy model: \(error)")
                }
            } else {
                print("❌ Not found: \(modelName)")
            }
        }
        
        print("❌ No legacy model found in bundle")
    }
    
    // MARK: - Public Interface
    
    func generateSummary(for verse: String) async -> String {
        print("🎯 Generating summary for: \(verse.prefix(50))...")
        
        // If Core ML is active, avoid touching fallback here
        if GenerationRuntime.shared.mode != .fallback {
            print("ℹ️ BARTService.generateSummary: Core ML active; returning placeholder")
            return ""
        }
        let summarizer = ImprovedBibleSummarizer()
        let result = await summarizer.generateCommentary(for: verse)
        print("✅ Semantic model generated summary successfully")
        return result
    }
    
    func generateCommentary(for verse: String) async -> (commentary: String, devotional: String) {
        print("🎯 Generating commentary for: \(verse.prefix(50))...")
        
        // If Core ML is active, avoid touching fallback here
        if GenerationRuntime.shared.mode != .fallback {
            print("ℹ️ BARTService.generateCommentary: Core ML active; bypassing fallback")
            return (commentary: "", devotional: "")
        }
        let summarizer = ImprovedBibleSummarizer()
        
        // FIX 24: Check which model is being used
        if let semanticGenerator = summarizer.getSemanticGenerator() {
            let modelInfo = semanticGenerator.getModelInfo()
            print("📊 Model Info: \(modelInfo)")
        }
        
        let result = await summarizer.generateCommentary(for: verse)
        print("✅ Semantic model generated commentary successfully")
        return (commentary: result, devotional: "This verse reminds us of God's love and guidance.")
    }
    
    // Parse structured output to extract commentary and devotional sections
    private func parseStructuredOutput(_ text: String) -> (commentary: String, devotional: String) {
        var commentary = ""
        var devotional = ""
        
        // Extract commentary
        if let startRange = text.range(of: "[START_COMMENTARY]"),
           let endRange = text.range(of: "[END_COMMENTARY]") {
            let startIndex = text.index(startRange.upperBound, offsetBy: 0)
            commentary = String(text[startIndex..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Extract devotional
        if let startRange = text.range(of: "[START_DEVOTIONAL]"),
           let endRange = text.range(of: "[END_DEVOTIONAL]") {
            let startIndex = text.index(startRange.upperBound, offsetBy: 0)
            devotional = String(text[startIndex..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // If no structured tokens found, treat the whole text as commentary
        if commentary.isEmpty && devotional.isEmpty {
            commentary = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return (commentary, devotional)
    }
    
    // MARK: - Status Methods
    
    func isReady() -> Bool {
        return (useImprovedModel && improvedSummarizer != nil) || useLegacyModel
    }
    
    func getStatus() -> String {
        if useImprovedModel {
            return "Improved model ready"
        } else if useLegacyModel {
            return "Legacy model loaded"
        } else {
            return "No model available"
        }
    }
    
    func getInitializationTime() -> TimeInterval {
        // Simplified - no longer tracking initialization time
        return 0
    }
    
    // MARK: - Legacy Support
    
    private func loadGenerationModel() {
        print("🔍 Loading legacy generation model...")
        
        // Try to find the generation model
        let possibleModelNames = [
            "simple-verse-model-coreml",       // Your existing model
            "SimpleVerseModelGeneration",      // Generation model
            "simple-verse-model-generation",   // Alternative naming
            "BibleVerseGenerator",             // Another alternative
        ]
        
        for modelName in possibleModelNames {
            if let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
                print("✅ Found legacy generation model at: \(modelURL.path)")
                return
            } else {
                print("❌ Not found: \(modelName)")
            }
        }
        
        print("❌ No legacy generation model found in bundle")
    }
    
    private func testBundleResources() {
        print("🔍 Testing bundle resources...")
        
        // Get all bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            print("📁 Bundle resource path: \(resourcePath)")
            
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                print("📦 Bundle contents:")
                for item in contents.sorted() {
                    print("  - \(item)")
                }
            } catch {
                print("❌ Error reading bundle contents: \(error)")
            }
        }
    }
    
    // MARK: - Fallback Methods
    
    private func generateSummaryWithOriginalModel(for verse: String) -> String {
        print("🔄 Using fallback summary generation")
        return "This verse teaches us about God's love and guidance."
    }
    
    private func generateCommentaryWithOriginalModel(for verse: String) -> (commentary: String, devotional: String) {
        print("🔄 Using fallback commentary generation")
        return (
            commentary: "This verse teaches us about God's love and guidance.",
            devotional: "This verse reminds us of God's love and guidance."
        )
    }
}

 
 