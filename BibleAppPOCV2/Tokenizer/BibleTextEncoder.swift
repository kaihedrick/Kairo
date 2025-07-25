// filepath: BibleAppPOCV2/Tokenizer/BibleTextEncoder.swift
import Foundation
import CoreML

/// Service class for handling Bible text encoding using Core ML
class BibleTextEncoder: ObservableObject {
    
    // MARK: - Properties
    private var model: MLModel?
    private var tokenizer: BARTTokenizer?
    
    // Model configuration
    private let maxLength = 256
    private let embeddingDimension = 1024
    
    // MARK: - Published Properties
    @Published var isModelLoaded = false
    @Published var errorMessage: String?
    
    // MARK: - Initialization
    init() {
        loadModel()
        setupTokenizer()
    }
    
    // MARK: - Model Loading
    private func loadModel() {
        guard let modelURL = Bundle.main.url(forResource: "BibleSummarizer_encoder", withExtension: "mlmodelc") else {
            errorMessage = "Could not find BibleSummarizer_encoder.mlmodelc in app bundle"
            return
        }
        
        do {
            model = try MLModel(contentsOf: modelURL)
            isModelLoaded = true
            print("✅ Bible encoder model loaded successfully")
        } catch {
            errorMessage = "Error loading model: \(error.localizedDescription)"
            print("❌ Error loading model: \(error)")
        }
    }
    
    private func setupTokenizer() {
        tokenizer = BARTTokenizer()
    }
    
    // MARK: - Text Encoding
    /// Encode text and prefer generated_ids output if present, fallback to embeddings
    func encode(text: String) async -> [Float]? {
        guard let model = model else {
            DispatchQueue.main.async {
                self.errorMessage = "Model not loaded"
            }
            return nil
        }
        guard let tokenizer = tokenizer else {
            DispatchQueue.main.async {
                self.errorMessage = "Tokenizer not initialized"
            }
            return nil
        }
        do {
            // Tokenize input text
            let tokens = tokenizer.tokenizeToStrings(text)
            let inputIds = tokenizer.convertTokensToIds(tokens)
            // Create attention mask
            let attentionMask = Array(repeating: 1, count: min(inputIds.count, maxLength))
            // Pad/truncate sequences
            let paddedInputIds = padSequence(inputIds, to: maxLength)
            let paddedAttentionMask = padSequence(attentionMask, to: maxLength)
            // Create MLMultiArrays
            let inputIdsArray = try createMLMultiArray(from: paddedInputIds)
            let attentionMaskArray = try createMLMultiArray(from: paddedAttentionMask)
            // Create model input
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: inputIdsArray),
                "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
            ])
            // Run prediction
            let output = try await model.prediction(from: input)
            // Prefer generated_ids if present
            if let generatedIds = output.featureValue(for: "generated_ids")?.multiArrayValue {
                let tokenIds = (0..<generatedIds.count).map { Int(truncating: generatedIds[$0]) }
                print("🔢 Decoded token IDs: \(tokenIds)")
                // Optionally decode to text: let generatedText = tokenizer.decode(tokenIds)
                // If you want to return text, change return type to String and return generatedText
                // For now, return nil to indicate generated_ids present (or handle as needed)
                return nil
            }
            // Fallback to embeddings
            return extractEmbeddings(from: output)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Error during encoding: \(error.localizedDescription)"
            }
            return nil
        }
    }
    
    // MARK: - Text Similarity
    /// Calculate similarity between two texts
    func similarity(between text1: String, and text2: String) async -> Float? {
        async let embeddings1 = encode(text: text1)
        async let embeddings2 = encode(text: text2)
        
        guard let emb1 = await embeddings1, let emb2 = await embeddings2 else {
            return nil
        }
        
        return cosineSimilarity(emb1, emb2)
    }
    
    // MARK: - Batch Processing
    /// Encode multiple texts in batch
    func encodeBatch(texts: [String]) async -> [[Float]] {
        var results: [[Float]] = []
        
        for text in texts {
            if let embedding = await encode(text: text) {
                results.append(embedding)
            } else {
                results.append([]) // Empty array for failed encodings
            }
        }
        
        return results
    }
    
    // MARK: - Helper Methods
    private func padSequence(_ sequence: [Int], to length: Int) -> [Int] {
        if sequence.count >= length {
            return Array(sequence.prefix(length))
        } else {
            let padTokenId = 1 // PAD token
            return sequence + Array(repeating: padTokenId, count: length - sequence.count)
        }
    }
    
    private func createMLMultiArray(from array: [Int]) throws -> MLMultiArray {
        let shape = [1, array.count] as [NSNumber]
        let multiArray = try MLMultiArray(shape: shape, dataType: .int32)
        
        for (index, value) in array.enumerated() {
            multiArray[index] = NSNumber(value: value)
        }
        
        return multiArray
    }
    
    private func extractEmbeddings(from output: MLFeatureProvider) -> [Float]? {
        guard let outputFeature = output.featureValue(for: "embeddings"),
              let multiArray = outputFeature.multiArrayValue else {
            return nil
        }
        
        // Output shape: [batch_size, sequence_length, embedding_dim]
        let sequenceLength = multiArray.shape[1].intValue
        let embeddingDim = multiArray.shape[2].intValue
        
        var embeddings: [Float] = []
        var validTokenCount = 0
        
        // Average pooling across sequence length
        for embIdx in 0..<embeddingDim {
            var sum: Float = 0
            var count = 0
            
            for seqIdx in 0..<sequenceLength {
                let linearIndex = seqIdx * embeddingDim + embIdx
                if linearIndex < multiArray.count {
                    sum += multiArray[linearIndex].floatValue
                    count += 1
                }
            }
            
            if count > 0 {
                embeddings.append(sum / Float(count))
                if embIdx == 0 { validTokenCount = count }
            }
        }
        
        return embeddings.count == embeddingDimension ? embeddings : nil
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count && a.count > 0 else { return 0.0 }
        
        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0.0
    }
}

// MARK: - Core ML Input Structure
class BibleEncoderInput: MLFeatureProvider {
    let input_ids: MLMultiArray
    let attention_mask: MLMultiArray
    
    init(input_ids: MLMultiArray, attention_mask: MLMultiArray) {
        self.input_ids = input_ids
        self.attention_mask = attention_mask
    }
    
    var featureNames: Set<String> {
        return ["input_ids", "attention_mask"]
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "input_ids":
            return MLFeatureValue(multiArray: input_ids)
        case "attention_mask":
            return MLFeatureValue(multiArray: attention_mask)
        default:
            return nil
        }
    }
}

// MARK: - Error Types
enum BibleEncoderError: Error, LocalizedError {
    case modelNotLoaded
    case tokenizerNotInitialized
    case invalidInput
    case encodingFailed
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Bible encoder model is not loaded"
        case .tokenizerNotInitialized:
            return "Tokenizer is not initialized"
        case .invalidInput:
            return "Invalid input text"
        case .encodingFailed:
            return "Failed to encode text"
        }
    }
}
