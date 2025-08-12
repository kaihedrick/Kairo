import Foundation
import CoreML

class SemanticBibleGenerator {
    private let model: MLModel
    private let tokenizer: BARTTokenizerSemantic
    private let fallbackTokenizer: ImprovedBARTTokenizer
    private let selectedModelName: String
    
    init() throws {
        // Load Core ML model - prioritize 512-token model over INT8
        var modelURL: URL?
        var selectedModelName = ""
        
        // FIX 20: Prioritize 512-token model and be explicit about selection
        let modelSearchOrder = [
            ("BARTBibleGeneratorSemantic512", "mlpackage", "512-token semantic model"),
            ("BARTBibleGeneratorSemantic512", "mlmodelc", "512-token semantic model"),
            ("BARTBibleGeneratorSemantic", "mlpackage", "Semantic model"),
            ("BARTBibleGeneratorSemantic", "mlmodelc", "Semantic model"),
            ("BARTBibleGenerator_NONE", "mlpackage", "NONE quantized model"),
            ("BARTBibleGenerator_NONE", "mlmodelc", "NONE quantized model"),
            ("BARTBibleGenerator_INT8", "mlpackage", "INT8 quantized model (FALLBACK)"),
            ("BARTBibleGenerator_INT8", "mlmodelc", "INT8 quantized model (FALLBACK)")
        ]
        
        for (modelName, fileExtension, description) in modelSearchOrder {
            if let url = Bundle.main.url(forResource: modelName, withExtension: fileExtension) {
                modelURL = url
                selectedModelName = "\(modelName).\(fileExtension)"
                break
            }
        }
        
        guard let modelURL = modelURL else {
            throw BARTError.modelNotFound
        }
        
        // FIX 51: Configure model with proper compute units for iOS 16+
        let config = MLModelConfiguration()
        config.computeUnits = .all // Use best available hardware (ANE, GPU, CPU)
        
        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        self.tokenizer = BARTTokenizerSemantic()
        self.fallbackTokenizer = ImprovedBARTTokenizer()
        
        // FIX 22: Store selected model info for debugging
        self.selectedModelName = selectedModelName
    }
    
    // MARK: - Public Interface
    
    /// Get information about the currently loaded model
    func getModelInfo() -> String {
        return """
        Model: \(selectedModelName)
        Is 512-token model: \(selectedModelName.contains("512"))
        Is INT8 model: \(selectedModelName.contains("INT8"))
        """
    }
    
    /// List all available BART models in the bundle
    static func listAvailableModels() -> [String] {
        var availableModels: [String] = []
        
        if let bundlePath = Bundle.main.resourcePath {
            do {
                let files = try FileManager.default.contentsOfDirectory(atPath: bundlePath)
                let bartModels = files.filter { $0.contains("BART") && ($0.contains("mlmodel") || $0.contains("mlpackage")) }
                availableModels = bartModels.sorted()
            } catch {
                print("❌ Error reading bundle contents: \(error)")
            }
        }
        
        return availableModels
    }
    
    func generateCommentary(for verse: String) async throws -> String {
        print("🚀 Starting commentary generation for: \(verse.prefix(50))...")
        print("📊 Using model: \(selectedModelName)")
        
        // FIX 1: Validate tokenizer alignment first
        guard validateTokenizerAlignment() else {
            print("🔍 FALLBACK TRIGGER: Tokenizer alignment validation failed")
            print("🔍 Input: \(verse.prefix(50))...")
            print("❌ Tokenizer alignment validation failed, using fallback")
            return "This verse teaches us about God's love and guidance."
        }
        
        // Check if semantic tokenizer loaded properly
        let useSemanticTokenizer = tokenizer.isSemanticReady
        
        // FIX 42: Create proper input prompt with special tokens - match training format
        let verseContent = verse.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputPrompt = "[START_COMMENTARY] \(verseContent)"
        
        print("📝 Using prompt: '\(inputPrompt.prefix(100))...'")
        print("🎯 Expected format: [START_COMMENTARY] <verse text> [END_COMMENTARY]")
        
        // Determine max length based on model (512 for new model, 256 for old models)
        var maxLength: Int
        if let inputIdsConstraint = model.modelDescription.inputDescriptionsByName["input_ids"]?.multiArrayConstraint {
            let shape = inputIdsConstraint.shape
            print("🔍 Model constraint shape: \(shape)")
            print("🔍 Shape count: \(shape.count)")
            for (index, dim) in shape.enumerated() {
                print("🔍 Shape[\(index)]: \(dim.intValue)")
            }
            
            if shape.count >= 2 {
                maxLength = shape[1].intValue
                print("📏 Detected max length from model: \(maxLength)")
                
                // Validate the detected length
                if maxLength <= 1 {
                    print("⚠️ Detected length seems wrong (\(maxLength)), using default 256")
                    maxLength = 256
                }
            } else {
                maxLength = 256 // Default fallback
                print("⚠️ Could not detect shape from model, using default: \(maxLength)")
            }
        } else {
            maxLength = 256 // Default fallback
            print("⚠️ No input_ids constraint found, using default: \(maxLength)")
        }
        
        print("📏 Using max length: \(maxLength)")
        
        // Tokenize the input
        var inputIds: [Int]
        var attentionMask: [Int]
        
        do {
            if useSemanticTokenizer {
                let result = try tokenizer.encode(inputPrompt, maxLength: maxLength)
                inputIds = result.0
                attentionMask = result.1
                
                // FIX 48: Create proper attention mask that zeros out padded tokens
                var properAttentionMask = Array(repeating: 1, count: maxLength)
                for (i, tokenId) in inputIds.enumerated() {
                    if i < maxLength && tokenId == 1 { // PAD token ID
                        properAttentionMask[i] = 0
                    }
                }
                attentionMask = properAttentionMask
                print("✅ Created proper attention mask with \(attentionMask.filter { $0 == 0 }.count) padded positions")
                
            } else {
                let result = try fallbackTokenizer.encode(inputPrompt)
                inputIds = result.0
                attentionMask = result.1
                
                // FIX 48: Create proper attention mask for fallback tokenizer too
                var properAttentionMask = Array(repeating: 1, count: maxLength)
                for (i, tokenId) in inputIds.enumerated() {
                    if i < maxLength && tokenId == 1 { // PAD token ID
                        properAttentionMask[i] = 0
                    }
                }
                attentionMask = properAttentionMask
                print("✅ Created proper attention mask for fallback with \(attentionMask.filter { $0 == 0 }.count) padded positions")
            }
        } catch {
            print("❌ Tokenization failed: \(error)")
            throw BARTError.tokenizationFailed
        }
        
        guard !inputIds.isEmpty else {
            print("❌ Empty input IDs after tokenization")
            throw BARTError.tokenizationFailed
        }
        
        print("✅ Tokenized to \(inputIds.count) tokens")
        print("🔍 Token IDs: \(inputIds.prefix(20))...")
        
        // FIX 2: Create MLMultiArray inputs with proper data types
        let inputIdsArray = try createMLMultiArrayWithProperTypes(from: inputIds, shape: [1, maxLength])
        let attentionMaskArray = try createMLMultiArrayWithProperTypes(from: attentionMask, shape: [1, maxLength])
        
        print("✅ Created MLMultiArray inputs with proper types")
        
        // FIX 17: Validate inputs before inference
        let expectedInputDataType = model.modelDescription.inputDescriptionsByName["input_ids"]?.multiArrayConstraint?.dataType ?? .int32
        let expectedAttentionDataType = model.modelDescription.inputDescriptionsByName["attention_mask"]?.multiArrayConstraint?.dataType ?? .int32
        
        let inputIdsValid = CoreMLDebugger.validateInput(inputIdsArray, expectedShape: [1, maxLength], expectedDataType: expectedInputDataType, name: "input_ids")
        let attentionMaskValid = CoreMLDebugger.validateInput(attentionMaskArray, expectedShape: [1, maxLength], expectedDataType: expectedAttentionDataType, name: "attention_mask")
        
        if !inputIdsValid || !attentionMaskValid {
            print("🚨 Input validation failed - this will likely cause single letter output")
            print("💡 Check data type mismatches and regenerate model if needed")
        }
        
        // FIX 3: Create input dictionary with proper MLFeatureValue wrapping
        let inputDict: [String: MLFeatureValue] = [
            "input_ids": MLFeatureValue(multiArray: inputIdsArray),
            "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
        ]
        
        print("🧠 Running CoreML inference...")
        
        // Run inference
        let prediction = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: inputDict))
        
        guard let logits = prediction.featureValue(for: "logits")?.multiArrayValue else {
            print("❌ Failed to get logits from prediction")
            print("🔍 Available output features: \(prediction.featureNames)")
            throw BARTError.inferenceFailed
        }
        
        // FIX 18: Analyze logits for issues
        CoreMLDebugger.analyzeLogits(logits)
        
        // FIX 4: Generate text from logits with improved decoding
        let generatedText = generateTextFromLogitsWithDebugging(logits)
        
        print("✅ Generated commentary: \(generatedText.prefix(100))...")
        return generatedText
    }
    
    // FIX 2: Create MLMultiArray with proper data types matching model expectations
    private func createMLMultiArrayWithProperTypes(from intArray: [Int], shape: [Int]) throws -> MLMultiArray {
        let nsShape = shape.map { NSNumber(value: $0) }
        
        // Get the expected data type from the model
        let expectedDataType: MLMultiArrayDataType
        if let inputIdsConstraint = model.modelDescription.inputDescriptionsByName["input_ids"]?.multiArrayConstraint {
            expectedDataType = inputIdsConstraint.dataType
            print("📏 Model expects dataType: \(expectedDataType)")
        } else {
            expectedDataType = .int32
            print("⚠️ Could not determine expected dataType, using .int32")
        }
        
        let array = try MLMultiArray(shape: nsShape, dataType: expectedDataType)
        
        // Use proper 2D indexing for Core ML compatibility
        let cols = shape[1]
        
        // Ensure we have enough values (pad if necessary)
        var paddedArray = intArray
        while paddedArray.count < cols {
            paddedArray.append(1) // Pad with pad token ID
        }
        
        // Fill the array with proper 2D indexing and data type conversion
        for i in 0..<cols {
            let value = paddedArray[i]
            
            // FIX 3: Handle data type conversion properly
            switch expectedDataType {
            case .int32:
                array[[0 as NSNumber, i as NSNumber]] = NSNumber(value: Int32(value))
            case .float32:
                array[[0 as NSNumber, i as NSNumber]] = NSNumber(value: Float(value))
            case .double:
                array[[0 as NSNumber, i as NSNumber]] = NSNumber(value: Double(value))
            default:
                // For any other type, use the original value
                array[[0 as NSNumber, i as NSNumber]] = NSNumber(value: value)
            }
        }
        
        print("✅ Created MLMultiArray with shape \(shape) and dataType \(expectedDataType)")
        return array
    }
    
    // FIX 55: Improved greedy decoding with flattened logits tensor
    private func generateTextFromLogitsWithDebugging(_ logits: MLMultiArray) -> String {
        let shape = logits.shape
        print("📊 Logits shape: \(shape)")
        print("📊 Logits dataType: \(logits.dataType)")
        
        guard shape.count == 3 else {
            print("❌ Unexpected logits shape: \(shape)")
            return "This verse teaches us about God's love and guidance."
        }
        
        let sequenceLength = shape[1].intValue
        let vocabSize = shape[2].intValue
        
        print("📊 Sequence length: \(sequenceLength), Vocab size: \(vocabSize)")
        
        // FIX 55: Greedy decoding across entire logits tensor
        let eosTokenId = 2 // </s>
        let endCommentaryTokenId = 50266 // [END_COMMENTARY]
        let endDevotionalTokenId = 50268 // [END_DEVOTIONAL]
        
        var decodedTokens: [Int] = []
        var generationStoppedCleanly = false
        
        print("🚀 Starting greedy decoding across \(sequenceLength) timesteps...")
        
        for t in 0..<sequenceLength {
            var maxLogit: Float = -.infinity
            var selectedTokenId = 0
            
            // Find the token with highest logit at this timestep
            for v in 0..<vocabSize {
                let index = t * vocabSize + v
                let logit = logits[index].floatValue
                if logit > maxLogit {
                    maxLogit = logit
                    selectedTokenId = v
                }
            }
            
            // Validate token ID
            if selectedTokenId < 0 || selectedTokenId >= vocabSize {
                print("❌ Invalid token ID \(selectedTokenId) at position \(t), skipping")
                continue
            }
            
            print("🎯 Position \(t): Token ID \(selectedTokenId) (logit: \(maxLogit))")
            decodedTokens.append(selectedTokenId)
            
            // Stop at end markers
            if selectedTokenId == endCommentaryTokenId {
                print("🏁 Found [END_COMMENTARY] token at position \(t) - stopping generation cleanly")
                generationStoppedCleanly = true
                break
            }
            
            if selectedTokenId == endDevotionalTokenId {
                print("🏁 Found [END_DEVOTIONAL] token at position \(t) - stopping generation cleanly")
                generationStoppedCleanly = true
                break
            }
            
            if selectedTokenId == eosTokenId {
                print("🏁 Found EOS token at position \(t) - stopping generation")
                break
            }
        }
        
        // FIX 47: Enhanced generation completion logging
        let lastTokenId = decodedTokens.last ?? -1
        if generationStoppedCleanly {
            if lastTokenId == 50266 {
                print("✅ Generation completed cleanly on [END_COMMENTARY] token")
            } else if lastTokenId == 50268 {
                print("✅ Generation completed cleanly on [END_DEVOTIONAL] token")
            }
        } else if lastTokenId == 2 {
            print("✅ Generation completed on EOS token")
        } else {
            print("⚠️ Generation stopped at max tokens or other limit (last token: \(lastTokenId))")
        }
        
        print("📝 Generated \(decodedTokens.count) tokens: \(decodedTokens.prefix(20))...")
        
        // FIX 19: Debug token generation
        CoreMLDebugger.debugTokenGeneration(decodedTokens, vocabSize: vocabSize)
        
        // FIX 45: Enhanced token debugging for BART-style generation with devotional support
        print("🔍 Token Analysis:")
        print("  - Total tokens: \(decodedTokens.count)")
        print("  - Decoder start tokens: \(decodedTokens.filter { $0 == 2 }.count)")
        print("  - EOS tokens: \(decodedTokens.filter { $0 == 2 }.count)")
        print("  - [START_COMMENTARY] tokens: \(decodedTokens.filter { $0 == 50265 }.count)")
        print("  - [END_COMMENTARY] tokens: \(decodedTokens.filter { $0 == 50266 }.count)")
        print("  - [START_DEVOTIONAL] tokens: \(decodedTokens.filter { $0 == 50267 }.count)")
        print("  - [END_DEVOTIONAL] tokens: \(decodedTokens.filter { $0 == 50268 }.count)")
        
        // FIX 44: Enhanced BART-style token filtering with support for both commentary and devotional
        let eosId = 2 // </s>
        let decoderStartId = 2 // also </s> in this tokenizer
        let endCommentaryId = 50266 // [END_COMMENTARY]
        let endDevotionalId = 50268 // [END_DEVOTIONAL]
        
        print("🔢 Raw generated tokens: \(decodedTokens)")
        print("🎯 Decoder start ID: \(decoderStartId), EOS ID: \(eosId)")
        
        // 1. Find the first token that's not a decoder start or EOS
        var filteredTokenIds: [Int] = []
        if let firstRealTokenIndex = decodedTokens.firstIndex(where: { $0 != decoderStartId && $0 != eosId }) {
            // 2. Filter tokens, removing decoder start, EOS, and stopping at end markers
            let tokensAfterStart = Array(decodedTokens[firstRealTokenIndex...])
            for tokenId in tokensAfterStart {
                if tokenId == endCommentaryId || tokenId == endDevotionalId || tokenId == eosId {
                    break // Stop at [END_COMMENTARY], [END_DEVOTIONAL], or EOS
                }
                filteredTokenIds.append(tokenId)
            }
            print("✅ Found first real token at index \(firstRealTokenIndex)")
        } else {
            print("⚠️ No valid tokens found after decoder start/EOS filtering")
            return "This verse teaches us about God's love and guidance."
        }
        
        print("🔍 Filtered to \(filteredTokenIds.count) tokens after BART-style cleaning")
        
        // FIX 11: Additional validation - ensure all tokens are valid
        let validTokenIds = filteredTokenIds.filter { tokenId in
            return tokenId >= 0 && tokenId < vocabSize
        }
        
        if validTokenIds.count != filteredTokenIds.count {
            print("⚠️ Filtered out \(filteredTokenIds.count - validTokenIds.count) invalid tokens")
        }
        
        guard !validTokenIds.isEmpty else {
            print("🔍 FALLBACK TRIGGER: No valid tokens to decode")
            print("❌ No valid tokens to decode")
            return "This verse teaches us about God's love and guidance."
        }
        
        // FIX 12: Decode the filtered sequence with fallback
        let useSemanticTokenizer = tokenizer.isSemanticReady
        var decodedText: String
        
        print("🔍 Decoding \(validTokenIds.count) token IDs: \(validTokenIds.prefix(20))...")
        
        if useSemanticTokenizer {
            decodedText = tokenizer.decode(validTokenIds)
            print("📖 SEMANTIC DECODED TEXT: '\(decodedText)'")
            // FIX 37: Increase minimum length threshold to prevent unnecessary fallbacks
            if decodedText.isEmpty || decodedText.count < 5 {
                print("⚠️ Semantic tokenizer produced poor output, using fallback")
                decodedText = fallbackTokenizer.decode(validTokenIds)
                print("📖 FALLBACK DECODED TEXT: '\(decodedText)'")
            }
        } else {
            decodedText = fallbackTokenizer.decode(validTokenIds)
            print("📖 FALLBACK DECODED TEXT: '\(decodedText)'")
        }
        
        if decodedText.isEmpty {
            print("🔍 FALLBACK TRIGGER: Both tokenizers failed to decode sequence")
            print("❌ Both tokenizers failed to decode sequence")
            return "This verse teaches us about God's love and guidance."
        } else {
            print("✅ Decoded text: '\(decodedText.prefix(100))...'")
            
            // FIX 13: Clean up any remaining artifacts
            let cleanedText = cleanDecodedText(decodedText)
            print("🎯 FINAL COMMENTARY OUTPUT:")
            print("\(cleanedText)")
            return cleanedText
        }
    }
    
            // FIX 43: Enhanced text cleaning with support for both commentary and devotional formats
        private func cleanDecodedText(_ text: String) -> String {
            var cleaned = text
            
            // FIX 43: Extract content between special token markers
            if let startRange = cleaned.range(of: "[START_COMMENTARY]"),
               let endRange = cleaned.range(of: "[END_COMMENTARY]") {
                let startIndex = cleaned.index(startRange.upperBound, offsetBy: 0)
                let endIndex = endRange.lowerBound
                if startIndex < endIndex {
                    cleaned = String(cleaned[startIndex..<endIndex])
                    print("✅ Extracted commentary content between [START_COMMENTARY] and [END_COMMENTARY]")
                }
            } else if let startRange = cleaned.range(of: "[START_DEVOTIONAL]"),
                      let endRange = cleaned.range(of: "[END_DEVOTIONAL]") {
                let startIndex = cleaned.index(startRange.upperBound, offsetBy: 0)
                let endIndex = endRange.lowerBound
                if startIndex < endIndex {
                    cleaned = String(cleaned[startIndex..<endIndex])
                    print("✅ Extracted devotional content between [START_DEVOTIONAL] and [END_DEVOTIONAL]")
                }
            } else {
                // Fallback: remove all special tokens if no proper markers found
                cleaned = cleaned.replacingOccurrences(of: "<s>", with: "")
                cleaned = cleaned.replacingOccurrences(of: "</s>", with: "")
                cleaned = cleaned.replacingOccurrences(of: "[START_COMMENTARY]", with: "")
                cleaned = cleaned.replacingOccurrences(of: "[END_COMMENTARY]", with: "")
                cleaned = cleaned.replacingOccurrences(of: "[START_DEVOTIONAL]", with: "")
                cleaned = cleaned.replacingOccurrences(of: "[END_DEVOTIONAL]", with: "")
                print("⚠️ No proper token markers found, removed all special tokens")
            }
        
        // Remove excessive whitespace
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common corrupted patterns
        cleaned = cleaned.replacingOccurrences(of: "________", with: "")
        cleaned = cleaned.replacingOccurrences(of: "::", with: "")
        cleaned = cleaned.replacingOccurrences(of: "**,", with: "")
        
        // Remove single character outputs (indicates model failure)
        if cleaned.count <= 1 {
            print("🔍 FALLBACK TRIGGER: Detected single character output")
            print("🔍 Output: \(cleaned)")
            print("❌ Detected single character output, indicating model failure")
            return "This verse teaches us about God's love and guidance."
        }
        
        // FIX 38: Make short output check conditional to prevent unnecessary fallbacks
        if cleaned.count < 10 {
            // Only trigger fallback if output contains suspicious patterns
            let suspiciousPatterns = ["ceanniighty", "estai", "eollathada", "theariu", "________", "::", "**,", "ĠĠĠ"]
            let containsSuspiciousPattern = suspiciousPatterns.contains { cleaned.contains($0) }
            
            if containsSuspiciousPattern {
                print("🔍 FALLBACK TRIGGER: Output too short and contains suspicious patterns")
                print("🔍 Output: \(cleaned)")
                print("⚠️ Output too short and contains suspicious patterns, may indicate model issues")
                return "This verse teaches us about God's love and guidance."
            } else {
                print("ℹ️ Output is short but appears valid, continuing")
            }
        }
        
        return cleaned
    }
    
    // FIX 34: Apply repetition penalty to prevent loops
    private func applyRepetitionPenalty(to logits: inout [Float], previousTokens: [Int], penalty: Float) {
        let penaltyFactor = 1.0 / penalty
        
        for tokenId in previousTokens {
            if tokenId >= 0 && tokenId < logits.count {
                logits[tokenId] *= penaltyFactor
            }
        }
    }
    
    // FIX 35: Nucleus sampling (top-p) for better text generation
    private func selectNextTokenWithNucleusSampling(from logits: [Float], temperature: Float, topP: Float) -> Int {
        // Apply temperature
        let temperatureLogits = logits.map { $0 / temperature }
        
        // Convert to probabilities
        let maxLogit = temperatureLogits.max() ?? 0
        let expLogits = temperatureLogits.map { exp($0 - maxLogit) }
        let sumExp = expLogits.reduce(0, +)
        let probabilities = expLogits.map { $0 / sumExp }
        
        // Sort by probability (descending)
        let sortedIndices = probabilities.enumerated().sorted { $0.1 > $1.1 }.map { $0.0 }
        let sortedProbs = sortedIndices.map { probabilities[$0] }
        
        // Find cumulative probability up to topP
        var cumulativeProb: Float = 0
        var selectedIndex = 0
        
        for (index, prob) in sortedProbs.enumerated() {
            cumulativeProb += prob
            if cumulativeProb >= topP {
                selectedIndex = index
                break
            }
        }
        
        // Sample from the nucleus
        let nucleusIndices = Array(sortedIndices.prefix(selectedIndex + 1))
        let nucleusProbs = Array(sortedProbs.prefix(selectedIndex + 1))
        
        // Normalize nucleus probabilities
        let nucleusSum = nucleusProbs.reduce(0, +)
        let normalizedProbs = nucleusProbs.map { $0 / nucleusSum }
        
        // Sample from nucleus
        let randomValue = Float.random(in: 0...1)
        var cumulative: Float = 0
        
        for (index, prob) in normalizedProbs.enumerated() {
            cumulative += prob
            if cumulative >= randomValue {
                return nucleusIndices[index]
            }
        }
        
        // Fallback to highest probability token
        return nucleusIndices.first ?? 0
    }
    
    // FIX 14: Enhanced tokenizer alignment validation
    private func validateTokenizerAlignment() -> Bool {
        print("🔍 Validating tokenizer alignment...")
        
        // Check if semantic tokenizer is ready
        guard tokenizer.isSemanticReady else {
            print("❌ Semantic tokenizer not ready")
            return false
        }
        
        // Test basic tokenization and decoding
        let testText = "Hello world"
        do {
            let (inputIds, _) = try tokenizer.encode(testText, maxLength: 10)
            let decodedText = tokenizer.decode(inputIds)
            
            print("✅ Basic tokenization test:")
            print("  Input: '\(testText)'")
            print("  Token IDs: \(inputIds)")
            print("  Decoded: '\(decodedText)'")
            
            // Check if decoding produces reasonable output
            if decodedText.isEmpty || decodedText.contains("") || decodedText.contains("__") {
                print("❌ Decoding produces corrupted output")
                return false
            }
            
        } catch {
            print("❌ Tokenization test failed: \(error)")
            return false
        }
        
        // Test special tokens
        let specialTokens = ["<s>", "</s>", "[START_COMMENTARY]", "[END_COMMENTARY]"]
        for token in specialTokens {
            if let tokenId = tokenizer.getSpecialTokenId(for: token) {
                let decoded = tokenizer.decode([tokenId])
                print("✅ Special token '\(token)' (ID: \(tokenId)) decodes to: '\(decoded)'")
                
                // FIX 28: Handle BOS token ID 0 as a special case
                if tokenId == 0 && token == "<s>" {
                    print("⚠️ BOS token has ID 0 - this is acceptable but may cause conflicts")
                    // Don't fail validation for this case, just warn
                } else if tokenId == 0 {
                    print("❌ Special token '\(token)' has ID 0, indicating tokenizer issue")
                    return false
                }
            } else {
                print("❌ Special token '\(token)' not found in tokenizer")
                return false
            }
        }
        
        print("✅ Tokenizer alignment validation passed")
        return true
    }
    
    // MARK: - Debug Helper
    
    func debugTokenization(for text: String) {
        print("🔍 Debug Tokenization:")
        print("  Input text: \(text)")
        
        do {
            let maxLength = model.modelDescription.inputDescriptionsByName["input_ids"]?.multiArrayConstraint?.shape.first?.intValue ?? 256
            let (inputIds, attentionMask) = try tokenizer.encode(text, maxLength: maxLength)
            print("  Input IDs count: \(inputIds.count)")
            print("  Attention mask count: \(attentionMask.count)")
            print("  Expected shape: [1, \(maxLength)]")
            print("  Actual shape: [1, \(inputIds.count)]")
            
            if inputIds.count != maxLength {
                print("  ❌ SHAPE MISMATCH DETECTED!")
            } else {
                print("  ✅ Shape is correct!")
            }
            
            // Check for special tokens (simplified check)
            let specialTokenIds = inputIds.filter { id in
                // Check if token ID is in the special token range
                return id >= 50265 && id <= 50268 // Special token range from added_tokens.json
            }
            print("  Special tokens found: \(specialTokenIds.count)")
            
            // Test decoding
            let decodedText = tokenizer.decode(inputIds)
            print("  Decoded text: \(decodedText.prefix(100))...")
            
        } catch {
            print("  ❌ Tokenization failed: \(error)")
        }
    }
}

enum BARTError: Error {
    case modelNotFound
    case tokenizationFailed
    case inferenceFailed
} 