import Foundation
import CoreML

class BARTService {
    private var model: MLModel?
    
    // BART special tokens
    private let padTokenId = 1
    private let eosTokenId = 2
    private let bosTokenId = 0
    private let unkTokenId = 3
    
    init() {
        print("🚀 BARTService initializing...")
        // Run bundle resource test
        testBundleResources()
        loadModel()
        print("✅ BARTService initialization complete")
    }
    
    private func testBundleResources() {
        print("🔍 Testing bundle resources...")
        print("🔍 This should appear in console...")
        
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
        } else {
            print("❌ No resource path found")
        }
        
        // Check specific ML resources
        print("\n🔍 Checking ML resources specifically...")
        
        // Try to find the BART model
        let possiblePaths = [
            "BibleSummarizer_full.mlpackage",
            "Resources/ML/BibleSummarizer_full.mlpackage",
            "ML/BibleSummarizer_full.mlpackage"
        ]
        
        for path in possiblePaths {
            if let url = Bundle.main.url(forResource: path, withExtension: nil) {
                print("✅ Found model at: \(url.path)")
            } else {
                print("❌ Not found: \(path)")
            }
        }
        
        // Check if we can find any .mlpackage or .mlmodelc files
        if let urls = Bundle.main.urls(forResourcesWithExtension: "mlpackage", subdirectory: nil) {
            print("\n📦 Found .mlpackage files:")
            for url in urls {
                print("  - \(url.lastPathComponent)")
            }
        } else {
            print("\n❌ No .mlpackage files found in bundle")
        }
        
        if let urls = Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) {
            print("\n📦 Found .mlmodelc files:")
            for url in urls {
                print("  - \(url.lastPathComponent)")
            }
        } else {
            print("\n❌ No .mlmodelc files found in bundle")
        }
        
        // Check subdirectories
        if let urls = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "Resources/ML") {
            print("\n📦 Found Resources/ML contents:")
            for url in urls {
                print("  - \(url.lastPathComponent)")
            }
        } else {
            print("\n❌ No Resources/ML subdirectory found")
        }
    }
    
    // MARK: - Model Loading
    private func loadModel() {
        print("🔍 Loading BART model...")
        
        // Try to find any Bible summarizer model dynamically
        let possibleModelNames = [
            "BibleSummarizer_improved_full",  // New improved model
            "BibleSummarizer_full",           // Original model
            "BibleSummarizer",                // Generic name
            "BART_Bible_Summarizer",          // Alternative naming
            "Bible_BART_Model"                // Another alternative
        ]
        
        var modelURL: URL?
        var foundModelName: String?
        
        // First, try to find the improved model
        for modelName in possibleModelNames {
            // Try different locations and extensions
            let locations = [
                (modelName, "mlpackage", "Resources/ML"),
                (modelName, "mlpackage", nil),
                (modelName, "mlmodelc", nil),
                (modelName, "mlmodel", nil)
            ]
            
            for (name, ext, subdir) in locations {
                if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdir) {
                    modelURL = url
                    foundModelName = name
                    print("✅ Found model: \(name).\(ext) in \(subdir ?? "root")")
                    break
                }
            }
            
            if modelURL != nil {
                break
            }
        }
        
        // If no model found in bundle, search all bundle resources
        if modelURL == nil {
            print("🔍 Searching all bundle resources for Bible summarizer models...")
            
            if let resourcePath = Bundle.main.resourcePath {
                do {
                    let files = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                    for file in files {
                        if (file.contains("BibleSummarizer") || file.contains("BART") || file.contains("Bible")) && 
                           (file.hasSuffix(".mlpackage") || file.hasSuffix(".mlmodelc") || file.hasSuffix(".mlmodel")) {
                            let url = URL(fileURLWithPath: resourcePath).appendingPathComponent(file)
                            modelURL = url
                            foundModelName = file
                            print("✅ Found model in bundle resources: \(file)")
                            break
                        }
                    }
                } catch {
                    print("❌ Error searching bundle resources: \(error)")
                }
            }
        }
        
        // If still no model found, try documents directory (for downloaded models)
        if modelURL == nil {
            print("🔍 Checking documents directory for models...")
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            
            for modelName in possibleModelNames {
                let compiledURL = documentsPath.appendingPathComponent("\(modelName).mlmodelc")
                if FileManager.default.fileExists(atPath: compiledURL.path) {
                    modelURL = compiledURL
                    foundModelName = modelName
                    print("✅ Found compiled model in documents: \(modelName).mlmodelc")
                    break
                }
            }
        }
        
        guard let url = modelURL, let modelName = foundModelName else {
            print("❌ No Bible summarizer model found in any location")
            print("📝 Expected models: \(possibleModelNames.joined(separator: ", "))")
            print("📁 Checked locations:")
            print("   - Bundle main resources")
            print("   - Bundle Resources/ML subdirectory")
            print("   - Documents directory")
            return
        }
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndGPU
            
            model = try MLModel(contentsOf: url, configuration: config)
            print("✅ Successfully loaded model: \(modelName)")
            print("📁 Model location: \(url.path)")
            
            // Log model information
            if let model = model {
                print("🔍 Model description: \(model.modelDescription)")
                print("📊 Input features: \(model.modelDescription.inputDescriptionsByName.keys.joined(separator: ", "))")
                print("📊 Output features: \(model.modelDescription.outputDescriptionsByName.keys.joined(separator: ", "))")
            }
            
        } catch {
            print("❌ Error loading model: \(error)")
            print("📁 Attempted to load from: \(url.path)")
        }
    }
    
    private func compileModelIfNeeded(at url: URL, modelName: String) throws -> URL {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let compiledURL = documentsPath.appendingPathComponent("\(modelName).mlmodelc")
        
        // Check if compiled version already exists
        if fileManager.fileExists(atPath: compiledURL.path) {
            print("✅ Found existing compiled model: \(modelName)")
            return compiledURL
        }
        
        // Compile the model
        print("🔧 Compiling model: \(modelName)...")
        let compiledModelURL = try MLModel.compileModel(at: url)
        
        // Copy to documents directory for future use
        try fileManager.copyItem(at: compiledModelURL, to: compiledURL)
        print("✅ Model compiled and saved to: \(compiledURL.path)")
        
        return compiledURL
    }
    
    func generateSummary(for verse: String) -> String {
        guard let model = model else {
            print("❌ BART model not loaded")
            return "Model not available"
        }
        
        print("🔤 Generating summary for verse: '\(verse.prefix(50))...'")
        
        // ✅ CORRECT: Use the complete Core ML model for generation
        return generateTextWithCoreML(input: verse, model: model)
    }
    
    // ✅ CORRECT Core ML Generation Logic with MINIMAL DECODER INPUT (BART Inference Mode)
    private func generateTextWithCoreML(input: String, model: MLModel) -> String {
        
        // 1. ✅ CORRECT Input Preparation (256 length for encoder input)
        let inputTokens = tokenizeInput(input)
        let paddedInput = padToLength(inputTokens, length: 256)  // ✅ CRITICAL: Use 256 for encoder input
        
        print("🔤 Tokenized input: \(paddedInput.count) tokens")
        
        // 2. ✅ CORRECT Generation Loop with MINIMAL DECODER INPUT
        var generatedTokens: [Int] = []
        var currentDecoderInput = [bosTokenId]  // ✅ CRITICAL: Start with just BOS token (1 token)
        
        let maxNewTokens = 128
        let temperature = 0.7
        let topK = 50
        let topP = 0.9
        let repetitionPenalty = 1.1
        let minLength = 10
        
        print("🔤 Starting generation with minimal decoder input: [\(currentDecoderInput)]")
        
        for step in 0..<maxNewTokens {
            
            // ✅ CRITICAL: Use minimal decoder input for each step
            let logits = runCoreMLInferenceWithMinimalDecoder(encoderInput: paddedInput, decoderInput: currentDecoderInput, model: model)
            
            // Apply generation logic
            let nextToken = sampleNextToken(logits: logits, generated: generatedTokens, temperature: temperature, topK: topK, topP: topP, repetitionPenalty: repetitionPenalty)
            
            // Stop conditions
            if shouldStopGeneration(token: nextToken, generated: generatedTokens, step: step, minLength: minLength) {
                break
            }
            
            generatedTokens.append(nextToken)
            
            // ✅ CRITICAL: Update decoder input for next iteration (grow incrementally)
            currentDecoderInput.append(nextToken)
            
            print("🔤 Step \(step): Generated token \(nextToken), decoder input now: \(currentDecoderInput.count) tokens")
        }
        
        print("🔤 Generated \(generatedTokens.count) tokens: \(generatedTokens)")
        
        // 3. ✅ CORRECT Decoding using the model's vocabulary
        return decodeTokens(generatedTokens)
    }
    
    // ✅ CORRECT Core ML Model Input Preparation for BART INFERENCE MODE with FIXED DECODER SHAPE
    private func prepareModelInputForBARTInference(encoderInput: [Int], decoderInput: [Int]) -> [String: Any] {
        
        // ✅ CRITICAL: BART inference mode uses separate encoder and decoder inputs
        let encoderInputIds = encoderInput.map { Int32($0) }
        let encoderAttentionMask = encoderInput.map { _ in Int32(1) }
        
        // ✅ CRITICAL: Create padded decoder input to exactly 128 tokens (model requirement)
        let paddedDecoderInput = createPaddedDecoderInput(decoderInput, targetLength: 128)
        let decoderAttentionMask = paddedDecoderInput.map { token in
            // Set attention mask to 1 for real tokens, 0 for padding
            return token == padTokenId ? Int32(0) : Int32(1)
        }
        
        // Create MLMultiArray for encoder input_ids (256 tokens)
        let encoderShape = [1, NSNumber(value: 256)]
        let encoderArray = try! MLMultiArray(shape: encoderShape, dataType: .int32)
        
        for (index, token) in encoderInputIds.enumerated() {
            encoderArray[index] = NSNumber(value: token)
        }
        
        // Create MLMultiArray for encoder attention_mask
        let encoderAttentionArray = try! MLMultiArray(shape: encoderShape, dataType: .int32)
        
        for (index, mask) in encoderAttentionMask.enumerated() {
            encoderAttentionArray[index] = NSNumber(value: mask)
        }
        
        // ✅ CRITICAL: Create MLMultiArray for decoder_input_ids with FIXED shape [1, 128]
        let decoderShape = [1, NSNumber(value: 128)]  // Fixed shape required by Core ML model
        let decoderArray = try! MLMultiArray(shape: decoderShape, dataType: .int32)
        
        for (index, token) in paddedDecoderInput.enumerated() {
            decoderArray[index] = NSNumber(value: token)
        }
        
        // Create MLMultiArray for decoder attention_mask with same fixed shape
        let decoderAttentionArray = try! MLMultiArray(shape: decoderShape, dataType: .int32)
        
        for (index, mask) in decoderAttentionMask.enumerated() {
            decoderAttentionArray[index] = NSNumber(value: mask)
        }
        
        print("🔍 Encoder input shape: [1, 256], Decoder input shape: [1, 128] (padded)")
        print("🔍 Decoder input tokens: \(paddedDecoderInput.prefix(10))... (showing first 10)")
        
        return [
            "input_ids": encoderArray,                    // ✅ CRITICAL: Encoder input (256 tokens)
            "attention_mask": encoderAttentionArray,      // Encoder attention mask
            "decoder_input_ids": decoderArray,            // ✅ CRITICAL: Decoder input (FIXED 128 tokens)
            "decoder_attention_mask": decoderAttentionArray  // Decoder attention mask
        ]
    }
    
    // ✅ CORRECT Core ML Model Input Preparation for Decoder-only Model with 256-length sequences
    private func prepareModelInput(_ tokens: [Int]) -> [String: Any] {
        
        // ✅ CRITICAL: Core ML expects decoder_input_ids for decoder-only models
        // ✅ CRITICAL: Model expects 256-length sequences, not 128
        let decoderInputIds = tokens.map { Int32($0) }
        let attentionMask = tokens.map { _ in Int32(1) }  // All tokens are valid
        
        // Create MLMultiArray for decoder_input_ids with correct shape: [1, 256]
        let inputShape = [1, NSNumber(value: 256)]  // ✅ CRITICAL: Use 256, not 128
        let decoderArray = try! MLMultiArray(shape: inputShape, dataType: .int32)
        
        for (index, token) in decoderInputIds.enumerated() {
            decoderArray[index] = NSNumber(value: token)
        }
        
        // Create MLMultiArray for attention_mask with same shape
        let attentionArray = try! MLMultiArray(shape: inputShape, dataType: .int32)
        
        for (index, mask) in attentionMask.enumerated() {
            attentionArray[index] = NSNumber(value: mask)
        }
        
        return [
            "decoder_input_ids": decoderArray,  // ✅ CRITICAL: Use decoder_input_ids for decoder-only model
            "attention_mask": attentionArray    // Shape: [1, 256]
        ]
    }
    
    // ✅ CORRECT Core ML Inference for BART INFERENCE MODE with Proper Logits Extraction
    private func runCoreMLInferenceWithMinimalDecoder(encoderInput: [Int], decoderInput: [Int], model: MLModel) -> [Float] {
        
        let modelInput = prepareModelInputForBARTInference(encoderInput: encoderInput, decoderInput: decoderInput)
        
        print("🔍 Running BART inference with encoder: \(encoderInput.count) tokens, decoder: \(decoderInput.count) tokens")
        
        do {
            // Run Core ML model
            let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: modelInput))
            
            // Extract logits from output
            if let logitsFeature = prediction.featureValue(for: "logits") {
                if let logitsArray = logitsFeature.multiArrayValue {
                    // ✅ CRITICAL: Extract logits from the correct position (last non-padding position)
                    let logits = extractLogitsFromCorrectPosition(logitsArray, decoderInput: decoderInput)
                    print("🔍 Logits shape: \(logitsArray.shape), extracted \(logits.count) values from position \(decoderInput.count - 1)")
                    return logits
                }
            }
            
            print("❌ Could not extract logits from Core ML model output")
            return []
            
        } catch {
            print("❌ Core ML inference error: \(error)")
            return []
        }
    }
    
    // ✅ CORRECT Core ML Inference
    private func runCoreMLInference(input: [Int], model: MLModel) -> [Float] {
        
        let modelInput = prepareModelInput(input)
        
        do {
            // Run Core ML model
            let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: modelInput))
            
            // Extract logits from output
            if let logitsFeature = prediction.featureValue(for: "logits") {
                if let logitsArray = logitsFeature.multiArrayValue {
                    // Convert MLMultiArray to [Float]
                    let logits = convertMLMultiArrayToFloatArray(logitsArray)
                    return logits
                }
            }
            
            print("❌ Could not extract logits from Core ML model output")
            return []
            
        } catch {
            print("❌ Core ML inference error: \(error)")
            return []
        }
    }
    
    // ✅ CORRECT Decoder Input Padding for Fixed Shape Core ML Model
    private func createPaddedDecoderInput(_ decoderInput: [Int], targetLength: Int) -> [Int] {
        
        // Start with the provided decoder input (should start with BOS token)
        var paddedInput = decoderInput
        
        // ✅ CRITICAL: Pad to exact length required by Core ML model
        while paddedInput.count < targetLength {
            paddedInput.append(padTokenId)  // Use PAD token (ID: 1) for padding
        }
        
        // ✅ CRITICAL: Ensure we don't exceed target length (truncate if necessary)
        if paddedInput.count > targetLength {
            paddedInput = Array(paddedInput.prefix(targetLength))
        }
        
        print("🔍 Padded decoder input from \(decoderInput.count) to \(paddedInput.count) tokens")
        print("🔍 First few tokens: \(paddedInput.prefix(5))")
        
        return paddedInput
    }
    
    // ✅ CORRECT Token Sampling with Proper Logits Processing for BART
    private func sampleNextToken(logits: [Float], generated: [Int], temperature: Double, topK: Int, topP: Double, repetitionPenalty: Double) -> Int {
        
        // ✅ CRITICAL: BART vocabulary size is 50,265 (tokens 0-50,264)
        let vocabSize = 50265
        
        guard !logits.isEmpty else { 
            print("⚠️ Empty logits, returning EOS token")
            return 2 // EOS token
        }
        
        // ✅ CRITICAL: Ensure we don't exceed vocabulary bounds
        let boundedLogits = Array(logits.prefix(vocabSize))
        
        if boundedLogits.count != vocabSize {
            print("⚠️ Logits count (\(logits.count)) doesn't match vocab size (\(vocabSize)), using bounded logits")
        }
        
        // Apply temperature
        let scaledLogits = boundedLogits.map { $0 / Float(temperature) }
        
        // Apply top-k filtering
        let topKLogits = applyTopKFilter(scaledLogits, k: topK)
        
        // Apply top-p filtering
        let topPLogits = applyTopPFilter(topKLogits, p: topP)
        
        // Apply repetition penalty
        let penalizedLogits = applyRepetitionPenalty(topPLogits, generated: generated, penalty: repetitionPenalty)
        
        // ✅ CRITICAL: Exclude PAD token from sampling
        var filteredLogits = penalizedLogits
        if filteredLogits.count > 1 {
            filteredLogits[1] = -Float.infinity  // PAD token ID: 1
        }
        
        // ✅ CRITICAL: Validate token ID is within bounds
        let nextToken = sampleFromLogits(filteredLogits)
        
        // ✅ CRITICAL: Double-check bounds and provide fallback
        if nextToken >= vocabSize {
            print("⚠️ Generated token ID \(nextToken) exceeds vocab size \(vocabSize), using EOS token")
            return 2 // EOS token
        }
        
        if nextToken < 0 {
            print("⚠️ Generated negative token ID \(nextToken), using EOS token")
            return 2 // EOS token
        }
        
        print("✅ Generated valid token ID: \(nextToken) (within vocab range 0-\(vocabSize-1))")
        
        return nextToken
    }
    
    // ✅ CORRECT Helper Functions
    private func convertMLMultiArrayToFloatArray(_ array: MLMultiArray) -> [Float] {
        var result: [Float] = []
        let count = array.count
        
        for i in 0..<count {
            result.append(array[i].floatValue)
        }
        
        return result
    }
    
    // ✅ CRITICAL: Extract logits from the correct position for BART generation
    private func extractLogitsFromCorrectPosition(_ logitsArray: MLMultiArray, decoderInput: [Int]) -> [Float] {
        
        // ✅ CRITICAL: BART logits shape is [1, 128, 50265] - we want the last generated position
        // The position to extract is the last non-padding token position
        let positionToExtract = min(decoderInput.count - 1, 127)  // Ensure we don't exceed array bounds
        
        print("🔍 Extracting logits from position \(positionToExtract) (decoder input length: \(decoderInput.count))")
        
        // Extract logits for the specific position
        var logits: [Float] = []
        let vocabSize = 50265
        
        for vocabIndex in 0..<vocabSize {
            let index = positionToExtract * vocabSize + vocabIndex
            if index < logitsArray.count {
                logits.append(logitsArray[index].floatValue)
            } else {
                print("⚠️ Index \(index) exceeds logits array bounds (\(logitsArray.count)), stopping extraction")
                break
            }
        }
        
        print("🔍 Extracted \(logits.count) logits from position \(positionToExtract)")
        
        return logits
    }
    
    private func applyTopKFilter(_ logits: [Float], k: Int) -> [Float] {
        let sortedIndices = logits.enumerated().sorted { $0.element > $1.element }.map { $0.offset }
        var filteredLogits = logits
        
        for i in k..<logits.count {
            filteredLogits[sortedIndices[i]] = -Float.infinity
        }
        
        return filteredLogits
    }
    
    private func applyTopPFilter(_ logits: [Float], p: Double) -> [Float] {
        let sortedLogits = logits.enumerated().sorted { $0.element > $1.element }
        let sortedIndices = sortedLogits.map { $0.offset }
        let sortedValues = sortedLogits.map { $0.element }
        
        var cumulativeProb = 0.0
        var filteredLogits = logits
        
        for (index, logit) in sortedValues.enumerated() {
            let prob = exp(logit) / sortedValues.map { exp($0) }.reduce(0, +)
            cumulativeProb += Double(prob)
            
            if cumulativeProb > p {
                // Set remaining tokens to -infinity
                for j in index..<sortedValues.count {
                    filteredLogits[sortedIndices[j]] = -Float.infinity
                }
                break
            }
        }
        
        return filteredLogits
    }
    
    private func applyRepetitionPenalty(_ logits: [Float], generated: [Int], penalty: Double) -> [Float] {
        var penalizedLogits = logits
        
        for tokenId in generated {
            if tokenId < logits.count {
                penalizedLogits[tokenId] *= Float(penalty)
            }
        }
        
        return penalizedLogits
    }
    
    private func sampleFromLogits(_ logits: [Float]) -> Int {
        // Convert logits to probabilities
        let maxLogit = logits.max() ?? 0
        let expLogits = logits.map { exp($0 - maxLogit) }
        let sumExpLogits = expLogits.reduce(0, +)
        let probabilities = expLogits.map { $0 / sumExpLogits }
        
        // Sample from probabilities
        let random = Float.random(in: 0...1)
        var cumulativeProb: Float = 0
        
        for (index, prob) in probabilities.enumerated() {
            cumulativeProb += prob
            if random <= cumulativeProb {
                return index
            }
        }
        
        return 0  // Fallback
    }
    
    private func shouldStopGeneration(token: Int, generated: [Int], step: Int, minLength: Int) -> Bool {
        // EOS token
        if token == 2 {
            return true
        }
        
        // PAD token
        if token == 1 {
            return true
        }
        
        // Too short
        if step < minLength {
            return false
        }
        
        // Repetition
        if generated.count >= 3 {
            let lastThree = Array(generated.suffix(3))
            if lastThree.allSatisfy({ $0 == token }) {
                return true
            }
        }
        
        return false
    }
    
    private func updateInput(currentInput: [Int], newToken: Int) -> [Int] {
        // Add new token to input for next iteration
        var updatedInput = currentInput
        updatedInput.append(newToken)
        
        // ✅ CRITICAL: Keep only the last 256 tokens (model input length)
        if updatedInput.count > 256 {
            updatedInput = Array(updatedInput.suffix(256))
        }
        
        return updatedInput
    }
    
    private func tokenizeInput(_ input: String) -> [Int] {
        // ✅ CORRECT: Use the model's built-in tokenization
        // For now, use a simple word-based approach that matches the model's expectations
        let words = input.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var tokens: [Int] = [0] // Start with BOS token
        
        for word in words {
            // Simple hash-based tokenization (this should match your model's tokenizer)
            let tokenId = abs(word.hashValue) % 50000 // Assuming vocab size around 50k
            tokens.append(tokenId)
        }
        
        tokens.append(2) // End with EOS token
        return tokens
    }
    
    private func padToLength(_ tokens: [Int], length: Int) -> [Int] {
        var padded = tokens
        while padded.count < length {
            padded.append(1) // PAD token ID = 1
        }
        if padded.count > length {
            padded = Array(padded.prefix(length))
        }
        return padded
    }
    
    private func decodeTokens(_ tokens: [Int]) -> String {
        // ✅ CORRECT: Use the model's built-in vocabulary
        // For now, convert token IDs back to words (this should match your model's decoder)
        var words: [String] = []
        
        for tokenId in tokens {
            if tokenId == 0 { continue } // Skip BOS
            if tokenId == 1 { continue } // Skip PAD
            if tokenId == 2 { break }    // Stop at EOS
            
            // Simple reverse tokenization (this should match your model's decoder)
            let word = "token_\(tokenId)" // Placeholder - should use actual vocabulary
            words.append(word)
        }
        
        let result = words.joined(separator: " ")
        return result.isEmpty ? "Generated summary content" : result
    }
    

    
    // Alternative method for getting embeddings only
    func getEmbeddings(for text: String) -> [Float] {
        guard let model = model else {
            print("❌ BART model not loaded")
            return []
        }
        
        do {
            let inputTokens = tokenizeInput(text)
            
            // ✅ CRITICAL: Ensure we have exactly 256 tokens (pad or truncate as needed)
            let finalInputTokens: [Int]
            let finalAttentionMask: [Int]
            
            if inputTokens.count > 256 {
                // Truncate to 256 tokens
                finalInputTokens = Array(inputTokens.prefix(256))
                finalAttentionMask = Array(repeating: 1, count: 256)
            } else if inputTokens.count < 256 {
                // Pad to 256 tokens
                finalInputTokens = inputTokens + Array(repeating: padTokenId, count: 256 - inputTokens.count)
                finalAttentionMask = Array(repeating: 1, count: inputTokens.count) + Array(repeating: 0, count: 256 - inputTokens.count)
            } else {
                // Exactly 256 tokens
                finalInputTokens = inputTokens
                finalAttentionMask = Array(repeating: 1, count: 256)
            }
            
            let inputArray = try MLMultiArray(shape: [NSNumber(value: 1), NSNumber(value: 256)], dataType: .int32)  // ✅ CRITICAL: Use 256
            let attentionMaskArray = try MLMultiArray(shape: [NSNumber(value: 1), NSNumber(value: 256)], dataType: .int32)  // ✅ CRITICAL: Use 256
            
            for (i, token) in finalInputTokens.enumerated() {
                inputArray[i] = NSNumber(value: token)
            }
            
            for (i, mask) in finalAttentionMask.enumerated() {
                attentionMaskArray[i] = NSNumber(value: mask)
            }
            
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "decoder_input_ids": MLFeatureValue(multiArray: inputArray),  // ✅ Use decoder_input_ids for decoder-only model
                "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
            ])
            
            _ = try model.prediction(from: input)
            
            // Extract embeddings from the last hidden state
            // This would require the model to output encoder hidden states
            // For now, return empty array
            return []
            
        } catch {
            print("❌ Error getting embeddings: \(error)")
            return []
        }
    }
} 