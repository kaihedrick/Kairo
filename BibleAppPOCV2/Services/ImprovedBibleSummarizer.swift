import Foundation
import CoreML

// MARK: - Errors
enum BibleSummarizerError: Error, LocalizedError {
    case modelNotFound
    case tokenizationFailed
    case inferenceFailed
    case invalidInput
    case parsingFailed
    case invalidInputShape(String)
    case shapeMismatch(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "CoreML model not found in app bundle"
        case .tokenizationFailed:
            return "Failed to tokenize input text"
        case .inferenceFailed:
            return "Model inference failed"
        case .invalidInput:
            return "Invalid input provided"
        case .parsingFailed:
            return "Failed to parse model output"
        case .invalidInputShape(let message):
            return "Invalid input shape: \(message)"
        case .shapeMismatch(let message):
            return "Shape mismatch: \(message)"
        }
    }
}

// MARK: - Improved Bible Summarizer
@MainActor
class ImprovedBibleSummarizer {
    private var model: MLModel?
    private let tokenizer = ImprovedBARTTokenizer()
    private var semanticGenerator: SemanticBibleGenerator?
    private var commentaryGenerator: BibleCommentaryGenerator?
    private var didInit = false
    
    init() {
        // Try to initialize the semantic model first
        do {
            let semanticModel = try SemanticBibleGenerator()
            self.semanticGenerator = semanticModel
        } catch {
            self.semanticGenerator = nil
        }
        
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
            do {
                // Parse the verse to extract reference and text properly
                let (verseRef, verseText) = parseVerse(verse)
                
                let commentaryResult = await commentaryGen.generateCommentary(for: verseRef, verseText: verseText)
                if !commentaryResult.isEmpty && !commentaryResult.contains("Unable to generate commentary") {
                    return commentaryResult
                }
            } catch {
                // Continue to fallback
            }
        }
        
        // Try semantic generator second
        do {
            let semanticGen = try SemanticBibleGenerator()
            let result = try await semanticGen.generateCommentary(for: verse)
            return result
        } catch {
            // Continue to fallback
        }
        
        // Fallback to basic commentary
        return "This verse teaches us about God's love and guidance."
    }
    
    func generateDevotional(for verse: String) async -> String {
        // Try Bible commentary generator first (new model)
        if let commentaryGen = commentaryGenerator {
            do {
                // Parse the verse to extract reference and text properly
                let (verseRef, verseText) = parseVerse(verse)
                
                let commentaryResult = await commentaryGen.generateCommentary(for: verseRef, verseText: verseText)
                if !commentaryResult.isEmpty && !commentaryResult.contains("Unable to generate devotional") {
                    return commentaryResult
                }
            } catch {
                // Continue to fallback
            }
        }
        
        // Fallback to basic devotional
        return "This verse reminds us of God's love and guidance in our daily lives."
    }
    
    /// Get the semantic generator instance for debugging
    func getSemanticGenerator() -> SemanticBibleGenerator? {
        do {
            return try SemanticBibleGenerator()
        } catch {
            print("❌ Could not create semantic generator: \(error)")
            return nil
        }
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
        
        // If that doesn't work, try to find a pattern like "Chapter Verse Text"
        let chapterVersePattern = #"^(\d+)\s+(\d+)\s+(.+)$"#
        
        if let regex = try? NSRegularExpression(pattern: chapterVersePattern, options: []),
           let match = regex.firstMatch(in: verse, options: [], range: NSRange(verse.startIndex..., in: verse)) {
            
            let chapter = String(verse[Range(match.range(at: 1), in: verse)!])
            let verseNum = String(verse[Range(match.range(at: 2), in: verse)!])
            let text = String(verse[Range(match.range(at: 3), in: verse)!])
            
            // Try to infer the book from context or use a default
            let verseRef = "Chapter \(chapter):\(verseNum)"
            return (verseRef, text)
        }
        
        // If all else fails, use the simple approach but limit the verse reference
        let components = verse.components(separatedBy: " ")
        if components.count >= 3 {
            // Look for a pattern like "Book Chapter:Verse" or "Chapter Verse"
            let firstTwo = "\(components[0]) \(components[1])"
            
            // Check if the second component contains a colon (indicating verse reference)
            if components[1].contains(":") {
                let verseRef = firstTwo
                let verseText = components.dropFirst(2).joined(separator: " ")
                return (verseRef, verseText)
            } else if components.count >= 3 && components[2].contains(":") {
                // Pattern like "Book Chapter Verse:Number"
                let verseRef = "\(components[0]) \(components[1]):\(components[2].split(separator: ":")[1])"
                let verseText = components.dropFirst(3).joined(separator: " ")
                return (verseRef, verseText)
            } else {
                // Simple case: take first two words as reference
                let verseRef = firstTwo
                let verseText = components.dropFirst(2).joined(separator: " ")
                return (verseRef, verseText)
            }
        }
        
        // Fallback: return the whole string as text
        return ("Unknown", verse)
    }
    
    private func generateCommentaryWithOriginalModel(for verse: String) -> String {
        guard let model = model else {
            print("❌ Model not initialized")
            return "This verse teaches us about God's love and guidance."
        }
        
        print("🔤 Tokenizing verse...")
        
        // FIX 52: Use proper input prompt format to match training
        let inputPrompt = "[START_COMMENTARY] \(verse)"
        
        do {
            // Tokenize input
            let (inputIds, attentionMask) = try tokenizer.encode(inputPrompt)
            
            print("📊 Input IDs count: \(inputIds.count)")
            print("📊 Attention mask count: \(attentionMask.count)")
            
            // Create MLMultiArray inputs
            let inputIdsArray = try createMLMultiArray(from: inputIds)
            let attentionMaskArray = try createAttentionMaskMLMultiArray(from: attentionMask)
            
            // Create input dictionary
            let inputDict: [String: MLFeatureValue] = [
                "input_ids": MLFeatureValue(multiArray: inputIdsArray),
                "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
            ]
            
            print("🧠 Running model inference...")
            
            // Run inference
            let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: inputDict))
            
            // Extract output
            let possibleOutputNames = ["logits", "output_sequences", "encoder_outputs", "decoder_outputs"]
            var logits: MLMultiArray?
            
            for outputName in possibleOutputNames {
                if let feature = prediction.featureValue(for: outputName),
                   let multiArray = feature.multiArrayValue {
                    logits = multiArray
                    print("✅ Found output: \(outputName)")
                    break
                }
            }
            
            guard let logits = logits else {
                print("❌ No valid output feature found. Available features: \(prediction.featureNames)")
                return "This verse teaches us about God's love and guidance."
            }
            
            print("📊 Logits shape: \(logits.shape)")
            
            // Generate text from logits
            let generatedText = generateTextFromLogits(logits: logits, tokenizer: tokenizer)
            
            print("✅ Generated text: \(generatedText.prefix(100))...")
            return generatedText
            
        } catch {
            print("❌ Error during inference: \(error)")
            return "This verse teaches us about God's love and guidance."
        }
    }
    
    // MARK: - Original Model Initialization (Fallback)
    
    private func initializeModel() {
        guard !didInit else { return }
        didInit = true
        print("🔧 Initializing original model...")
        
        let possibleModelNames = [
            "bible_commentary_model",  // The actual model in the bundle
            "BARTBibleGenerator_INT8",
            "BARTBibleGenerator_NONE", 
            "BARTBibleGeneratorSemantic",
            "simple-verse-model-coreml"
        ]
        
        // List available ML files in bundle for debugging
        if let bundlePath = Bundle.main.resourcePath {
            do {
                let files = try FileManager.default.contentsOfDirectory(atPath: bundlePath)
                let mlFiles = files.filter { $0.contains(".ml") || $0.contains("model") }
                print("📁 Available ML files in bundle: \(mlFiles)")
            } catch {
                print("❌ Could not list bundle files: \(error)")
            }
        }
        
        for modelName in possibleModelNames {
            // Try .mlmodelc first
            if let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
                do {
                    let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
                    cfg.computeUnits = .cpuOnly
#else
                    cfg.computeUnits = .cpuAndNeuralEngine
#endif
                    self.model = try MLModel(contentsOf: modelURL, configuration: cfg)
                    print("✅ Successfully loaded model: \(modelName).mlmodelc")
                    
                    // Print model description for debugging
                    let modelDescription = model!.modelDescription
                    print("📊 Model input features: \(modelDescription.inputDescriptionsByName.keys)")
                    print("📊 Model output features: \(modelDescription.outputDescriptionsByName.keys)")
                    
                    return
                } catch {
                    print("❌ Failed to load model \(modelName).mlmodelc: \(error)")
                }
            }
            
            // Try .mlpackage if .mlmodelc not found
            if let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
                do {
                    let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
                    cfg.computeUnits = .cpuOnly
#else
                    cfg.computeUnits = .cpuAndNeuralEngine
#endif
                    self.model = try MLModel(contentsOf: modelURL, configuration: cfg)
                    print("✅ Successfully loaded model: \(modelName).mlpackage")
                    
                    // Print model description for debugging
                    let modelDescription = model!.modelDescription
                    print("📊 Model input features: \(modelDescription.inputDescriptionsByName.keys)")
                    print("📊 Model output features: \(modelDescription.outputDescriptionsByName.keys)")
                    
                    return
                } catch {
                    print("❌ Failed to load model \(modelName).mlpackage: \(error)")
                }
            }
        }
        
        print("❌ Could not find any available model in bundle")
    }
    
    // MARK: - Helper Functions (Original Implementation)
    
    private func createMLMultiArray(from intArray: [Int]) throws -> MLMultiArray {
        let shape = [1, NSNumber(value: 256)]
        let array = try MLMultiArray(shape: shape, dataType: .int32)
        
        for (index, value) in intArray.enumerated() {
            array[index] = NSNumber(value: value)
        }
        
        return array
    }
    
    private func createDecoderMLMultiArray(from intArray: [Int]) throws -> MLMultiArray {
        let shape = [1, NSNumber(value: 256)]
        let array = try MLMultiArray(shape: shape, dataType: .int32)
        
        for (index, value) in intArray.enumerated() {
            array[index] = NSNumber(value: value)
        }
        
        return array
    }
    
    private func createAttentionMaskMLMultiArray(from intArray: [Int]) throws -> MLMultiArray {
        let shape = [1, NSNumber(value: 256)]
        let array = try MLMultiArray(shape: shape, dataType: .int32)
        
        for (index, value) in intArray.enumerated() {
            array[index] = NSNumber(value: value)
        }
        
        return array
    }
    
    private func extractIntArray(from multiArray: MLMultiArray) -> [Int] {
        var result: [Int] = []
        for i in 0..<multiArray.count {
            let value = multiArray[i]
            let numberValue = value as NSNumber
            result.append(numberValue.intValue)
        }
        return result
    }
    
    private func generateTextFromLogits(logits: MLMultiArray, tokenizer: ImprovedBARTTokenizer) -> String {
        let shape = logits.shape
        guard shape.count == 3 else {
            print("❌ Unexpected logits shape: \(shape)")
            return "This verse teaches us about God's love and guidance."
        }
        
        let sequenceLength = shape[1].intValue
        let vocabSize = shape[2].intValue
        
        // Extract logits for the last position
        let lastPosition = sequenceLength - 1
        var logitsForPosition: [Float] = []
        
        for vocabIndex in 0..<vocabSize {
            let logitIndex = lastPosition * vocabSize + vocabIndex
            let logitValue = Float(logits[logitIndex].floatValue)
            logitsForPosition.append(logitValue)
        }
        
        // Apply temperature sampling
        let temperature: Float = 0.7
        let topK = 50
        let repetitionPenalty: Float = 1.1
        
        // Find max logit for numerical stability
        let maxLogit = logitsForPosition.max() ?? 0
        
        // Apply temperature and repetition penalty
        var adjustedLogits = logitsForPosition.enumerated().map { (index, logit) in
            let adjustedLogit = (logit - maxLogit) / temperature
            return (index, adjustedLogit)
        }
        
        // Apply repetition penalty (simplified)
        adjustedLogits = adjustedLogits.map { (index, logit) in
            return (index, logit * repetitionPenalty)
        }
        
        // Apply softmax
        let expLogits = adjustedLogits.map { exp(Double($0.1)) }
        let sumExpLogits = expLogits.reduce(0, +)
        let probabilities = expLogits.map { $0 / sumExpLogits }
        
        // Top-K sampling
        let topKIndices = Array(0..<vocabSize)
            .enumerated()
            .sorted { probabilities[$0.offset] > probabilities[$1.offset] }
            .prefix(topK)
            .map { $0.offset }
        
        // Sample from top-K
        let randomValue = Float.random(in: 0...1)
        var cumulativeProbability: Float = 0
        
        for index in topKIndices {
            cumulativeProbability += Float(probabilities[index])
            if randomValue <= cumulativeProbability {
                let predictedTokenId = index
                let token = tokenizer.decode([predictedTokenId])
                return token.isEmpty ? "This verse teaches us about God's love." : token
            }
        }
        
        // Fallback responses
        let fallbackResponses = [
            "This verse teaches us about God's love and guidance.",
            "This passage reminds us of God's faithfulness.",
            "These words show us the importance of faith.",
            "This verse encourages us to trust in the Lord.",
            "These scriptures reveal God's wisdom and grace."
        ]
        
        return fallbackResponses.randomElement() ?? "This verse teaches us about God's love and guidance."
    }
    
    private func debugTopTokens(logits: MLMultiArray, tokenizer: ImprovedBARTTokenizer, position: Int = 0) {
        let shape = logits.shape
        guard shape.count == 3 else { return }
        
        let vocabSize = shape[2].intValue
        var logitsForPosition: [Float] = []
        
        // Extract logits for the specified position
        for vocabIndex in 0..<vocabSize {
            let logitIndex = position * vocabSize + vocabIndex
            let logitValue = Float(logits[logitIndex].floatValue)
            logitsForPosition.append(logitValue)
        }
        
        // Get top 10 tokens
        let top10Indices = Array(0..<vocabSize)
            .enumerated()
            .sorted { logitsForPosition[$0.offset] > logitsForPosition[$1.offset] }
            .prefix(10)
        
        print("🔍 Top 10 tokens at position \(position):")
        for (rank, (tokenId, logit)) in top10Indices.enumerated() {
            let token = tokenizer.decode([tokenId])
            print("  \(rank + 1). ID: \(tokenId), Logit: \(logit), Token: '\(token)'")
        }
    }
}

// MARK: - Improved BART Tokenizer
class ImprovedBARTTokenizer {
    private var vocab: [String: Int] = [:]
    private var merges: [String] = []
    private var tokenizerConfig: [String: Any] = [:]
    
    // Special tokens from config
    private var bosToken: String = "<s>"
    private var eosToken: String = "</s>"
    private var unkToken: String = "<unk>"
    private var padToken: String = "<pad>"
    private var maskToken: String = "<mask>"
    
    // Token IDs
    private var bosTokenId: Int = 0
    private var eosTokenId: Int = 2
    private var unkTokenId: Int = 3
    private var padTokenId: Int = 1
    private var maskTokenId: Int = 4
    
    // Special tokens for structured output
    private var startCommentaryToken: String = "[START_COMMENTARY]"
    private var endCommentaryToken: String = "[END_COMMENTARY]"
    private var startDevotionalToken: String = "[START_DEVOTIONAL]"
    private var endDevotionalToken: String = "[END_DEVOTIONAL]"
    
    init() {
        loadTokenizer()
    }
    
    private func loadTokenizer() {
        // Load vocabulary
        if let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "json"),
           let vocabData = try? Data(contentsOf: vocabURL),
           let vocabDict = try? JSONSerialization.jsonObject(with: vocabData) as? [String: Int] {
            self.vocab = vocabDict
        }
        
        // Load tokenizer config
        if let configURL = Bundle.main.url(forResource: "tokenizer_config", withExtension: "json"),
           let configData = try? Data(contentsOf: configURL),
           let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
            self.tokenizerConfig = config
            
            // Update special tokens from config
            if let bosToken = config["bos_token"] as? String { self.bosToken = bosToken }
            if let eosToken = config["eos_token"] as? String { self.eosToken = eosToken }
            if let unkToken = config["unk_token"] as? String { self.unkToken = unkToken }
            if let padToken = config["pad_token"] as? String { self.padToken = padToken }
            if let maskToken = config["mask_token"] as? String { self.maskToken = maskToken }
            
            // Update token IDs from vocabulary
            bosTokenId = vocab[bosToken] ?? 0
            eosTokenId = vocab[eosToken] ?? 2
            unkTokenId = vocab[unkToken] ?? 3
            padTokenId = vocab[padToken] ?? 1
            maskTokenId = vocab[maskToken] ?? 4
            
            // Load additional special tokens
            if let additionalTokens = config["additional_special_tokens"] as? [String] {
                for token in additionalTokens {
                    if token == startCommentaryToken || token == endCommentaryToken ||
                       token == startDevotionalToken || token == endDevotionalToken {
                        // These tokens should already be in vocabulary
                    }
                }
            }
        }
        
        // Try to load merges.txt if available
        if let mergesURL = Bundle.main.url(forResource: "merges", withExtension: "txt"),
           let mergesData = try? Data(contentsOf: mergesURL),
           let mergesString = String(data: mergesData, encoding: .utf8) {
            self.merges = mergesString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        }
    }
    
    func encode(_ text: String) throws -> (inputIds: [Int], attentionMask: [Int]) {
        // ⚠️ CRITICAL: Model was compiled with 256-token specification
        let maxLength = 256  // Model's expected sequence length (compiled spec)
        
        // Implement proper BPE tokenization following the guide's best practices
        var inputIds: [Int] = []
        
        // Add BOS token
        inputIds.append(bosTokenId)
        
        // Pre-tokenize: split on whitespace and handle spaces properly
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        for (index, word) in words.enumerated() {
            // Handle space prefix: first word gets no space, others get Ġ prefix
            let wordToTokenize = index == 0 ? word : "Ġ" + word
            
            // Try to find the word in vocabulary first
            if let id = vocab[wordToTokenize] {
                inputIds.append(id)
            } else {
                // If not found, try without space prefix
                if let id = vocab[word] {
                    inputIds.append(id)
                } else {
                    // Apply BPE merges if available
                    let tokens = applyBPEMerges(to: wordToTokenize)
                    for token in tokens {
                        if let id = vocab[token] {
                            inputIds.append(id)
                        } else {
                            // Fallback: split into characters
                            for char in token {
                                let charString = String(char)
                                if let id = vocab[charString] {
                                    inputIds.append(id)
                                } else {
                                    inputIds.append(unkTokenId)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Add EOS token
        inputIds.append(eosTokenId)
        
        // ⚠️ CRITICAL: Ensure we have exactly maxLength tokens (pad or truncate as needed)
        let finalInputIds: [Int]
        let finalAttentionMask: [Int]
        
        if inputIds.count > maxLength {
            // Truncate to maxLength tokens, but keep the beginning and end
            let keepFromStart = maxLength - 10  // Keep most from start, leave room for EOS
            let startTokens = Array(inputIds.prefix(keepFromStart))
            let endTokens = [eosTokenId]  // Always keep EOS token
            finalInputIds = startTokens + endTokens + Array(repeating: padTokenId, count: maxLength - startTokens.count - endTokens.count)
            finalAttentionMask = Array(repeating: 1, count: startTokens.count + endTokens.count) + Array(repeating: 0, count: maxLength - startTokens.count - endTokens.count)
            print("⚠️ Truncated tokens from \(inputIds.count) to \(maxLength) (kept beginning and end)")
        } else if inputIds.count < maxLength {
            // Pad to maxLength tokens
            finalInputIds = inputIds + Array(repeating: padTokenId, count: maxLength - inputIds.count)
            finalAttentionMask = Array(repeating: 1, count: inputIds.count) + Array(repeating: 0, count: maxLength - inputIds.count)
            print("⚠️ Padded tokens from \(inputIds.count) to \(maxLength)")
        } else {
            // Exactly maxLength tokens
            finalInputIds = inputIds
            finalAttentionMask = Array(repeating: 1, count: maxLength)
        }
        
        print("🔤 Tokenized '\(text.prefix(50))...' into \(finalInputIds.count) tokens (256-token model)")
        print("🔤 Attention mask length: \(finalAttentionMask.count)")
        print("🔤 Input text length: \(text.count) characters, \(words.count) words")
        
        return (finalInputIds, finalAttentionMask)
    }
    
    func encode256(_ text: String) throws -> (inputIds: [Int], attentionMask: [Int]) {
        // Alias for encode method - matches the integration guide
        return try encode(text)
    }
    
    func decode(_ ids: [Int]) -> String {
        // Create reverse vocabulary mapping
        let reverseVocab = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
        
        var tokens: [String] = []
        for id in ids {
            if let token = reverseVocab[id] {
                tokens.append(token)
            } else {
                tokens.append("<UNK>")
            }
        }
        
        // Join tokens and handle BPE-style tokens
        var result = tokens.joined(separator: " ")
        
        // Handle BPE-style space prefixes (Ġ)
        result = result.replacingOccurrences(of: "Ġ", with: " ")
        
        // Clean up extra spaces
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.trimmingCharacters(in: .whitespaces)
        
        return result
    }
    
    // MARK: - BPE Implementation
    
    private func applyBPEMerges(to word: String) -> [String] {
        guard !merges.isEmpty else {
            // No merges available, return word as single token
            return [word]
        }
        
        // Start with individual characters
        var tokens = word.map { String($0) }
        
        // Apply merge rules iteratively
        var merged = true
        while merged {
            merged = false
            
            for mergeRule in merges {
                let parts = mergeRule.components(separatedBy: " ")
                guard parts.count == 2 else { continue }
                
                let first = parts[0]
                let second = parts[1]
                
                // Look for adjacent pairs to merge
                for i in 0..<(tokens.count - 1) {
                    if tokens[i] == first && tokens[i + 1] == second {
                        // Merge the pair
                        let mergedToken = first + second
                        tokens[i] = mergedToken
                        tokens.remove(at: i + 1)
                        merged = true
                        break
                    }
                }
                
                if merged { break }
            }
        }
        
        return tokens
    }
    
    // MARK: - Public Helper Methods
    
    func createDecoderInput() -> [Int] {
        // Create decoder input starting with BOS token and padded to 256 tokens
        return [bosTokenId] + Array(repeating: padTokenId, count: 255)
    }
    
    func getBosTokenId() -> Int {
        return bosTokenId
    }
    
    func getPadTokenId() -> Int {
        return padTokenId
    }
    
    func getEosTokenId() -> Int {
        return eosTokenId
    }
    
    func getUnkTokenId() -> Int {
        return unkTokenId
    }
    
    // MARK: - Diagnostic Functions
    
    func debugTokenizerAlignment(for text: String) {
        print("🔍 Tokenizer Alignment Diagnostic:")
        print("  Input text: '\(text)'")
        
        do {
            let (inputIds, attentionMask) = try encode(text)
            print("  Encoded token IDs: \(inputIds.prefix(20))...")
            print("  Attention mask: \(attentionMask.prefix(20))...")
            
            // Decode back to text
            let decodedText = decode(inputIds)
            print("  Decoded text: '\(decodedText)'")
            
            // Check for special tokens
            print("  Special tokens found:")
            for (index, id) in inputIds.enumerated() {
                if id == bosTokenId {
                    print("    BOS token at position \(index)")
                } else if id == eosTokenId {
                    print("    EOS token at position \(index)")
                } else if id == padTokenId {
                    print("    PAD token at position \(index)")
                } else if id == unkTokenId {
                    print("    UNK token at position \(index)")
                }
            }
            
            // Check for Ġ characters (space markers)
            let decodedTokens = decode(inputIds).components(separatedBy: " ")
            let hasSpaceMarkers = decodedTokens.contains { $0.contains("Ġ") }
            print("  Contains space markers (Ġ): \(hasSpaceMarkers)")
            
        } catch {
            print("  ❌ Tokenization failed: \(error)")
        }
    }
    
    func debugVocabStats() {
        print("🔍 Vocabulary Statistics:")
        print("  Total vocabulary size: \(vocab.count)")
        print("  BPE merges loaded: \(merges.count)")
        
        // Check for common tokens
        let commonTokens = ["<s>", "</s>", "<pad>", "<unk>", "<mask>", "Ġthe", "Ġis", "Ġand"]
        print("  Common token IDs:")
        for token in commonTokens {
            if let id = vocab[token] {
                print("    '\(token)': \(id)")
            } else {
                print("    '\(token)': NOT FOUND")
            }
        }
        
        // Check special tokens from config
        print("  Special token IDs from config:")
        print("    BOS: \(bosTokenId) ('\(bosToken)')")
        print("    EOS: \(eosTokenId) ('\(eosToken)')")
        print("    PAD: \(padTokenId) ('\(padToken)')")
        print("    UNK: \(unkTokenId) ('\(unkToken)')")
        print("    MASK: \(maskTokenId) ('\(maskToken)')")
    }
} 