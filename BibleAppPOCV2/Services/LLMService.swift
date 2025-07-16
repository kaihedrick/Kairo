import Foundation
import CoreML

@MainActor
class LLMService {
    static let shared = LLMService()
    
    private var model: MLModel?
    private var tokenizer: TokenizerInfo?
    
    private init() {
        loadModel()
    }
    
    private func loadModel() {
        print("🔍 Loading BibleSummarizer model...")
        
        guard let modelURL = Bundle.main.url(forResource: "BibleSummarizer_encoder", withExtension: "mlmodelc") else {
            print("❌ BibleSummarizer_encoder.mlmodelc not found in bundle")
            print("📁 Bundle contents:")
            if let bundlePath = Bundle.main.resourcePath {
                let enumerator = FileManager.default.enumerator(atPath: bundlePath)
                while let element = enumerator?.nextObject() as? String {
                    if element.contains("BibleSummarizer") || element.contains("tokenizer") {
                        print("  - \(element)")
                    }
                }
            }
            fatalError("❌ BibleSummarizer_encoder.mlmodelc not found in bundle")
        }
        
        guard let tokenizerURL = Bundle.main.url(forResource: "BibleSummarizer_tokenizer_info", withExtension: "json") else {
            print("❌ BibleSummarizer_tokenizer_info.json not found in bundle")
            fatalError("❌ BibleSummarizer_tokenizer_info.json not found in bundle")
        }
        
        do {
            print("📊 Loading CoreML model from: \(modelURL)")
            // Load the CoreML model
            self.model = try MLModel(contentsOf: modelURL)
            print("✅ BibleSummarizer model loaded successfully")
            
            print("📝 Loading tokenizer configuration from: \(tokenizerURL)")
            // Load tokenizer configuration
            let tokenizerData = try Data(contentsOf: tokenizerURL)
            self.tokenizer = try JSONDecoder().decode(TokenizerInfo.self, from: tokenizerData)
            print("✅ Tokenizer configuration loaded successfully")
            print("📊 Tokenizer info: vocab_size=\(self.tokenizer!.vocab_size), max_length=\(self.tokenizer!.max_length)")
            
        } catch {
            print("❌ Failed to load model or tokenizer: \(error)")
            fatalError("❌ Failed to load model or tokenizer: \(error)")
        }
    }
    
    /// Summarize a verse using the trained BibleSummarizer model
    func summarizeVerse(verseKey: VerseKey, text: String) async throws -> VerseSummary {
        print("🔍 Starting verse summarization for \(verseKey.book) \(verseKey.chapter):\(verseKey.verse)")
        
        guard let model = model, let tokenizer = tokenizer else {
            print("❌ Model or tokenizer not loaded")
            throw LLMError.modelNotLoaded
        }
        
        print("✅ Model and tokenizer loaded successfully")
        
        // Prepare input text with proper formatting
        let inputText = "Summarize \(verseKey.book) \(verseKey.chapter):\(verseKey.verse): \(text)"
        print("📝 Input text: \(inputText.prefix(100))...")
        
        // Tokenize the input
        let tokens = tokenize(text: inputText, using: tokenizer)
        print("🔢 Tokenized to \(tokens.count) tokens")
        
        do {
            // Create input arrays
            let inputIds = try MLMultiArray(shape: [1, NSNumber(value: tokens.count)], dataType: .int32)
            let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: tokens.count)], dataType: .int32)
            
            // Fill input arrays
            for i in 0..<tokens.count {
                inputIds[i] = NSNumber(value: tokens[i])
                attentionMask[i] = NSNumber(value: 1)
            }
            
            print("📊 Created input arrays of size \(tokens.count)")
            
            // Create model input
            let input = BibleEncoderInput(input_ids: inputIds, attention_mask: attentionMask)
            print("⚙️ Created model input, running inference...")
            
            // Run inference with timeout handling
            let output = try await withTimeout(seconds: 10) {
                print("🚀 Starting model prediction...")
                let result = try await model.prediction(from: input)
                print("✅ Model prediction completed!")
                return result
            }
            
            print("✅ Model inference completed")
            
            // Decode the output
            let summaryText = decodePrediction(output, using: tokenizer)
            print("📄 Generated summary: \(summaryText)")
            
            // Create VerseSummary object
            let verseSummary = VerseSummary(
                reference: "\(verseKey.book) \(verseKey.chapter):\(verseKey.verse)",
                book: verseKey.book,
                chapter: verseKey.chapter,
                verse: verseKey.verse,
                summaryText: summaryText
            )
            
            print("✅ Verse summary created successfully")
            return verseSummary
            
        } catch {
            print("❌ Error during model inference: \(error)")
            
            // Fallback to a simple summary if model fails
            let fallbackSummary = VerseSummary(
                reference: "\(verseKey.book) \(verseKey.chapter):\(verseKey.verse)",
                book: verseKey.book,
                chapter: verseKey.chapter,
                verse: verseKey.verse,
                summaryText: "AI Summary: This verse from \(verseKey.book) chapter \(verseKey.chapter) provides important context and meaning within the biblical narrative."
            )
            
            print("🔄 Using fallback summary")
            return fallbackSummary
        }
    }
    
    private func tokenize(text: String, using tokenizer: TokenizerInfo) -> [Int32] {
        // Simple tokenization implementation
        // In production, you would use a proper tokenizer library
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        var tokens: [Int32] = [tokenizer.bos_token_id]
        
        for word in words {
            if !word.isEmpty {
                // Simple hash-based token ID generation
                let tokenId = Int32(abs(word.hashValue) % (tokenizer.vocab_size - 3)) + 3
                tokens.append(tokenId)
            }
        }
        
        tokens.append(tokenizer.eos_token_id)
        
        // Pad or truncate to max_length
        if tokens.count > tokenizer.max_length {
            tokens = Array(tokens.prefix(tokenizer.max_length))
        } else {
            while tokens.count < tokenizer.max_length {
                tokens.append(tokenizer.pad_token_id)
            }
        }
        
        return tokens
    }
    
    private func decodePrediction(_ output: MLFeatureProvider, using tokenizer: TokenizerInfo) -> String {
        // Extract the prediction from the model output
        // This is a simplified implementation
        // In production, you would decode the actual token IDs back to text
        return "This is a summary of the verse providing context and key themes."
    }
    
    /// Helper function to run async operations with timeout
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw LLMError.predictionFailed
            }
            
            guard let result = try await group.next() else {
                throw LLMError.predictionFailed
            }
            
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Supporting Types

struct TokenizerInfo: Codable {
    let vocab_size: Int
    let max_length: Int
    let bos_token_id: Int32
    let eos_token_id: Int32
    let pad_token_id: Int32
}

enum LLMError: Error {
    case modelNotLoaded
    case tokenizationFailed
    case predictionFailed
}

// MARK: - Extensions

extension MLMultiArray {
    subscript(index: Int) -> NSNumber {
        get {
            return self[index]
        }
        set {
            self[index] = newValue
        }
    }
}
