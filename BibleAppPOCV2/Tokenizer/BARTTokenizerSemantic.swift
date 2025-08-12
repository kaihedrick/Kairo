import Foundation

class BARTTokenizerSemantic {
    private var vocab: [String: Int] = [:]
    private var merges: [String] = []
    private var specialTokens: [String: Int] = [:]
    
    // Special token IDs
    private var bosTokenId: Int = 0
    private var eosTokenId: Int = 2
    private var padTokenId: Int = 1
    private var unkTokenId: Int = 3
    private var maskTokenId: Int = 4
    
    // FIX 26: Handle BOS token ID 0 conflict
    private var hasBosTokenConflict: Bool {
        return bosTokenId == 0 && padTokenId == 0
    }
    
    // FIX 36: BART decoder start token (should be EOS for BART)
    var decoderStartTokenId: Int {
        return eosTokenId // BART standard: decoder starts with EOS token
    }
    
    // Special token strings
    private let bosToken: String = "<s>"
    private let eosToken: String = "</s>"
    private let padToken: String = "<pad>"
    private let unkToken: String = "<unk>"
    private let maskToken: String = "<mask>"
    
    init() {
        loadTokenizer()
    }
    
    private func loadTokenizer() {
        // Try multiple paths for each file to ensure they're found
        let searchPaths = [
            "Resources/ML/semantic_export/tokenizer",
            "tokenizer",
            ""
        ]
        
        // Load vocabulary
        var vocabLoaded = false
        for path in searchPaths {
            if let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "json", subdirectory: path.isEmpty ? nil : path) {
                if let vocabData = try? Data(contentsOf: vocabURL),
                   let vocabDict = try? JSONSerialization.jsonObject(with: vocabData) as? [String: Int] {
                    self.vocab = vocabDict
                    vocabLoaded = true
                    break
                }
            }
        }
        
        // Load merges
        var mergesLoaded = false
        for path in searchPaths {
            if let mergesURL = Bundle.main.url(forResource: "merges", withExtension: "txt", subdirectory: path.isEmpty ? nil : path) {
                if let mergesString = try? String(contentsOf: mergesURL, encoding: .utf8) {
                    self.merges = mergesString.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    mergesLoaded = true
                    break
                }
            }
        }
        
        // Load special tokens map
        var specialTokensLoaded = false
        for path in searchPaths {
            if let specialTokensURL = Bundle.main.url(forResource: "special_tokens_map", withExtension: "json", subdirectory: path.isEmpty ? nil : path) {
                if let specialTokensData = try? Data(contentsOf: specialTokensURL),
                   let specialTokensDict = try? JSONSerialization.jsonObject(with: specialTokensData) as? [String: Any] {
                    // Extract special tokens
                    for (token, value) in specialTokensDict {
                        if let id = value as? Int {
                            specialTokens[token] = id
                        }
                    }
                    specialTokensLoaded = true
                    break
                }
            }
        }
        
        // Load added tokens
        var addedTokensLoaded = false
        for path in searchPaths {
            if let addedTokensURL = Bundle.main.url(forResource: "added_tokens", withExtension: "json", subdirectory: path.isEmpty ? nil : path) {
                if let addedTokensData = try? Data(contentsOf: addedTokensURL),
                   let addedTokensArray = try? JSONSerialization.jsonObject(with: addedTokensData) as? [[String: Any]] {
                    for tokenInfo in addedTokensArray {
                        if let content = tokenInfo["content"] as? String,
                           let id = tokenInfo["id"] as? Int {
                            specialTokens[content] = id
                        }
                    }
                    addedTokensLoaded = true
                    break
                }
            }
        }
        
        // Load tokenizer config
        var configLoaded = false
        for path in searchPaths {
            if let configURL = Bundle.main.url(forResource: "tokenizer_config", withExtension: "json", subdirectory: path.isEmpty ? nil : path) {
                if let configData = try? Data(contentsOf: configURL),
                   let configDict = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
                    // Extract special tokens from config
                    if let bosToken = configDict["bos_token"] as? String,
                       let bosId = specialTokens[bosToken] {
                        bosTokenId = bosId
                    }
                    if let eosToken = configDict["eos_token"] as? String,
                       let eosId = specialTokens[eosToken] {
                        eosTokenId = eosId
                    }
                    if let padToken = configDict["pad_token"] as? String,
                       let padId = specialTokens[padToken] {
                        padTokenId = padId
                    }
                    if let unkToken = configDict["unk_token"] as? String,
                       let unkId = specialTokens[unkToken] {
                        unkTokenId = unkId
                    }
                    if let maskToken = configDict["mask_token"] as? String,
                       let maskId = specialTokens[maskToken] {
                        maskTokenId = maskId
                    }
                    configLoaded = true
                    break
                }
            }
        }
    }
    
    func encode(_ text: String, maxLength: Int = 256) throws -> (inputIds: [Int], attentionMask: [Int]) {
        // Tokenize with BPE
        let tokens = tokenizeWithBPE(text)
        
        // FIX 27: Handle BOS token ID 0 conflict
        var inputIds: [Int]
        if hasBosTokenConflict {
            // Skip BOS token if it conflicts with padding
            inputIds = []
        } else {
            // Add BOS token normally
            inputIds = [bosTokenId]
        }
        
        // Convert tokens to IDs
        for token in tokens {
            if let id = vocab[token] {
                inputIds.append(id)
            } else {
                inputIds.append(unkTokenId)
            }
        }
        
        // FIX 50: Add EOS token for BART models (but leave space for it)
        let maxContentLength = maxLength - 1 // Leave space for EOS token
        
        // Truncate to max content length
        if inputIds.count > maxContentLength {
            inputIds = Array(inputIds.prefix(maxContentLength))
        }
        
        // Add EOS token
        inputIds.append(eosTokenId)
        
        // Pad to exactly maxLength
        while inputIds.count < maxLength {
            inputIds.append(padTokenId)
        }
        
        // Ensure we have exactly maxLength tokens
        if inputIds.count != maxLength {
            inputIds = Array(inputIds.prefix(maxLength))
            while inputIds.count < maxLength {
                inputIds.append(padTokenId)
            }
        }
        
        // Create attention mask (1s for real tokens, 0s for padding)
        let realTokenCount = min(inputIds.count, maxLength)
        var attentionMask = Array(repeating: 1, count: realTokenCount)
        while attentionMask.count < maxLength {
            attentionMask.append(0)
        }
        
        return (inputIds, attentionMask)
    }
    
    private func tokenizeWithBPE(_ text: String) -> [String] {
        var tokens: [String] = []
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        
        for (wordIndex, word) in words.enumerated() {
            if word.isEmpty { continue }
            
            // Add space prefix for non-first words (BPE convention)
            let wordToTokenize = wordIndex == 0 ? word : "Ġ" + word
            
            if vocab[wordToTokenize] != nil {
                tokens.append(wordToTokenize)
            } else {
                let subTokens = splitWordWithBPE(wordToTokenize)
                tokens.append(contentsOf: subTokens)
            }
        }
        
        return tokens
    }
    
    // FIX 53: Improved BPE implementation that handles merges correctly
    private func splitWordWithBPE(_ word: String) -> [String] {
        var tokens: [String] = []
        var currentWord = word
        
        while !currentWord.isEmpty {
            var found = false
            
            // Try to find the longest matching merge
            for merge in merges.reversed() {
                if currentWord.hasPrefix(merge) {
                    tokens.append(merge)
                    currentWord = String(currentWord.dropFirst(merge.count))
                    found = true
                    break
                }
            }
            
            if !found {
                // If no merge found, check if the word exists in vocabulary
                if let id = vocab[currentWord] {
                    tokens.append(currentWord)
                    currentWord = ""
                } else {
                    // Take the first character as fallback
                    let firstChar = String(currentWord.prefix(1))
                    tokens.append(firstChar)
                    currentWord = String(currentWord.dropFirst())
                }
            }
        }
        
        return tokens
    }
    
    func decode(_ ids: [Int]) -> String {
        let reverseVocab = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
        let tokens = ids.compactMap { reverseVocab[$0] }
        
        // Join tokens and clean up
        var text = tokens.joined(separator: "")
        
        // Replace Ġ with spaces (BPE convention)
        text = text.replacingOccurrences(of: "Ġ", with: " ")
        
        // Clean up extra spaces
        text = text.replacingOccurrences(of: "  ", with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return text
    }
    
    // MARK: - Public Getters
    
    func getBosTokenId() -> Int { return bosTokenId }
    func getEosTokenId() -> Int { return eosTokenId }
    func getPadTokenId() -> Int { return padTokenId }
    func getUnkTokenId() -> Int { return unkTokenId }
    func getMaskTokenId() -> Int { return maskTokenId }
    
    // MARK: - Public Getters for Tokenizer Status
    
    func getSpecialTokenId(for token: String) -> Int? {
        return specialTokens[token]
    }
    
    var isLoaded: Bool {
        let hasVocab = vocab.count > 0
        let hasMerges = merges.count > 0
        let hasSpecialTokens = specialTokens.count > 0
        let hasRequiredTokens = validateRequiredTokens()
        
        print("🔍 Tokenizer Load Status:")
        print("  - Vocabulary: \(hasVocab) (\(vocab.count) tokens)")
        print("  - Merges: \(hasMerges) (\(merges.count) merges)")
        print("  - Special tokens: \(hasSpecialTokens) (\(specialTokens.count) tokens)")
        print("  - Required tokens: \(hasRequiredTokens)")
        
        return hasVocab && hasMerges && hasSpecialTokens && hasRequiredTokens
    }
    
    private func validateRequiredTokens() -> Bool {
        print("🔍 Validating required tokens...")
        print("  Special tokens keys: \(specialTokens.keys.sorted())")
        
        // Check standard special tokens
        let standardTokens = ["<s>", "</s>", "<pad>", "<unk>"]
        for token in standardTokens {
            if let id = specialTokens[token] {
                print("    ✅ '\(token)': \(id)")
            } else {
                print("    ❌ '\(token)': NOT FOUND")
                return false
            }
        }
        
        // Check custom special tokens
        let customTokens = ["[START_COMMENTARY]", "[END_COMMENTARY]", "[START_DEVOTIONAL]", "[END_DEVOTIONAL]"]
        for token in customTokens {
            if let id = specialTokens[token] {
                print("    ✅ '\(token)': \(id)")
            } else {
                print("    ❌ '\(token)': NOT FOUND")
                return false
            }
        }
        
        // Validate token IDs are not default values (but allow valid defaults)
        // BOS should be 0, EOS should be 2, PAD should be 1, UNK should be 3
        if let bosId = specialTokens["<s>"], bosId != 0 {
            print("    ❌ BOS token ID should be 0, got \(bosId)")
            return false
        }
        if let eosId = specialTokens["</s>"], eosId != 2 {
            print("    ❌ EOS token ID should be 2, got \(eosId)")
            return false
        }
        if let padId = specialTokens["<pad>"], padId != 1 {
            print("    ❌ PAD token ID should be 1, got \(padId)")
            return false
        }
        if let unkId = specialTokens["<unk>"], unkId != 3 {
            print("    ❌ UNK token ID should be 3, got \(unkId)")
            return false
        }
        
        // Validate custom tokens have the expected IDs
        if let startCommentaryId = specialTokens["[START_COMMENTARY]"], startCommentaryId != 50265 {
            print("    ❌ [START_COMMENTARY] should be 50265, got \(startCommentaryId)")
            return false
        }
        if let endCommentaryId = specialTokens["[END_COMMENTARY]"], endCommentaryId != 50266 {
            print("    ❌ [END_COMMENTARY] should be 50266, got \(endCommentaryId)")
            return false
        }
        if let startDevotionalId = specialTokens["[START_DEVOTIONAL]"], startDevotionalId != 50267 {
            print("    ❌ [START_DEVOTIONAL] should be 50267, got \(startDevotionalId)")
            return false
        }
        if let endDevotionalId = specialTokens["[END_DEVOTIONAL]"], endDevotionalId != 50268 {
            print("    ❌ [END_DEVOTIONAL] should be 50268, got \(endDevotionalId)")
            return false
        }
        
        print("    ✅ All required tokens validated successfully")
        return true
    }
    
    var vocabularyCount: Int {
        return vocab.count
    }
    
    var mergesCount: Int {
        return merges.count
    }
    
    // MARK: - Semantic Tokenizer Readiness
    
    var isSemanticReady: Bool {
        let basicLoaded = isLoaded
        let hasRequiredTokens = validateRequiredTokens()
        
        // FIX 29: Handle BOS token ID 0 conflict gracefully
        let hasBosConflict = hasBosTokenConflict
        let isReady = basicLoaded && hasRequiredTokens
        
        print("🔍 Semantic Tokenizer Readiness:")
        print("  - Basic loaded: \(basicLoaded)")
        print("  - Has required tokens: \(hasRequiredTokens)")
        print("  - BOS token conflict: \(hasBosConflict)")
        print("  - Ready for semantic generation: \(isReady)")
        
        if hasBosConflict {
            print("⚠️ BOS token ID 0 conflict detected - will skip BOS token during encoding")
        }
        
        return isReady
    }
    
    // MARK: - Diagnostic Functions
    
    func debugVocabStats() {
        print("🔍 Vocabulary Statistics:")
        print("  Total vocabulary size: \(vocab.count)")
        print("  BPE merges loaded: \(merges.count)")
        print("  Special tokens loaded: \(specialTokens.count)")
        
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
        print("  Special token IDs:")
        print("    BOS: \(bosTokenId) ('\(bosToken)')")
        print("    EOS: \(eosTokenId) ('\(eosToken)')")
        print("    PAD: \(padTokenId) ('\(padToken)')")
        print("    UNK: \(unkTokenId) ('\(unkToken)')")
        print("    MASK: \(maskTokenId) ('\(maskToken)')")
        
        // Check custom special tokens
        print("  Custom special tokens:")
        let customTokens = ["[START_COMMENTARY]", "[END_COMMENTARY]", "[START_DEVOTIONAL]", "[END_DEVOTIONAL]"]
        for token in customTokens {
            if let id = specialTokens[token] {
                print("    '\(token)': \(id)")
            } else {
                print("    '\(token)': NOT FOUND")
            }
        }
    }
    
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
} 