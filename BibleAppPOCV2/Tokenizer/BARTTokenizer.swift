import Foundation

/// Tokenizer for BART model with Bible-specific vocabulary
class BARTTokenizer {
    
    // MARK: - Properties
    private var vocabulary: [String: Int] = [:]
    private var reverseVocabulary: [Int: String] = [:]
    private var tokenizerConfig: [String: Any] = [:]
    
    // Special tokens
    private let padToken = "<pad>"
    private let bosToken = "<s>"
    private let eosToken = "</s>"
    private let unkToken = "<unk>"
    
    // MARK: - Initialization
    init() {
        loadVocabulary()
        loadConfig()
    }
    
    // MARK: - Loading Methods
    private func loadVocabulary() {
        guard let vocabURL = Bundle.main.url(forResource: "simplified_vocab", withExtension: "json") else {
            print("❌ Warning: Could not find simplified_vocab.json, using basic vocabulary")
            setupBasicVocabulary()
            return
        }
        
        do {
            let vocabData = try Data(contentsOf: vocabURL)
            let vocabDict = try JSONSerialization.jsonObject(with: vocabData) as? [String: Int]
            
            if let vocab = vocabDict {
                vocabulary = vocab
                reverseVocabulary = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
                print("✅ Loaded vocabulary with \(vocab.count) tokens")
            } else {
                setupBasicVocabulary()
            }
        } catch {
            print("❌ Error loading vocabulary: \(error)")
            setupBasicVocabulary()
        }
    }
    
    private func loadConfig() {
        guard let configURL = Bundle.main.url(forResource: "tokenizer_config", withExtension: "json") else {
            print("❌ Warning: Could not find tokenizer_config.json")
            return
        }
        
        do {
            let configData = try Data(contentsOf: configURL)
            if let config = try JSONSerialization.jsonObject(with: configData) as? [String: Any] {
                tokenizerConfig = config
                print("✅ Loaded tokenizer configuration")
            }
        } catch {
            print("❌ Error loading tokenizer config: \(error)")
        }
    }
    
    private func setupBasicVocabulary() {
        print("📝 Setting up basic vocabulary...")
        
        // Essential tokens
        vocabulary = [
            padToken: 1,
            eosToken: 2,
            bosToken: 0,
            unkToken: 3
        ]
        
        // Common Bible words with their token IDs
        let bibleWords = [
            "god": 31858, "lord": 30669, "jesus": 10287, "christ": 3771,
            "and": 463, "the": 627, "said": 26, "unto": 9635, "for": 1990,
            "not": 3654, "he": 700, "him": 12724, "his": 465, "they": 51,
            "them": 135, "their": 511, "you": 47, "your": 110, "have": 33,
            "had": 56, "was": 7325, "were": 58, "be": 1610, "been": 57,
            "being": 145, "is": 354, "are": 32, "will": 40, "shall": 42065,
            "would": 74, "in": 179, "on": 15, "at": 23, "to": 7, "from": 31,
            "with": 19, "by": 30, "of": 9, "as": 25, "but": 53, "or": 50,
            "heaven": 18478, "earth": 6872, "light": 1109, "darkness": 11228,
            "water": 514, "sea": 3403, "land": 1212, "tree": 2195,
            "man": 313, "woman": 1590, "people": 82, "nation": 1226,
            "house": 790, "city": 343, "mountain": 6485, "valley": 18406,
            "word": 1234, "words": 1617, "say": 224, "saying": 584,
            "come": 283, "came": 376, "go": 213, "went": 439, "see": 192,
            "saw": 1265, "hear": 1568, "heard": 1982, "know": 216,
            "knew": 1266, "give": 492, "gave": 851, "take": 185, "took": 1220,
            "make": 146, "made": 156, "day": 1208, "night": 1135, "time": 86,
            "year": 614, "years": 1087, "life": 281, "death": 1372,
            "son": 979, "father": 1150, "mother": 2949, "brother": 2138,
            "sister": 6621, "king": 2745, "prophet": 19323, "priest": 11503,
            "temple": 4830, "altar": 17968, "sacrifice": 7615, "prayer": 6009,
            "faith": 3123, "love": 657, "peace": 1987, "joy": 5010,
            "hope": 1840, "truth": 2517, "righteousness": 35636
        ]
        
        // Add Bible words to vocabulary
        for (word, id) in bibleWords {
            vocabulary[word] = id
        }
        
        // Create reverse vocabulary
        reverseVocabulary = Dictionary(uniqueKeysWithValues: vocabulary.map { ($1, $0) })
        
        print("✅ Basic vocabulary setup complete with \(vocabulary.count) tokens")
    }
    
    // MARK: - Tokenization Methods
    /// Tokenize text into tokens
    func tokenize(_ text: String) -> [String] {
        // Simple word-based tokenization
        let cleanedText = text.lowercased()
            .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let words = cleanedText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        return words
    }
    
    /// Convert tokens to IDs
    func convertTokensToIds(_ tokens: [String]) -> [Int] {
        return tokens.map { token in
            vocabulary[token] ?? vocabulary[unkToken] ?? 3
        }
    }
    
    /// Convert IDs back to tokens
    func convertIdsToTokens(_ ids: [Int]) -> [String] {
        return ids.map { id in
            reverseVocabulary[id] ?? unkToken
        }
    }
    
    /// Decode IDs to text
    func decode(_ ids: [Int]) -> String {
        let tokens = convertIdsToTokens(ids)
        return tokens
            .filter { !isSpecialToken($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Encode text to IDs in one step
    func encode(_ text: String, maxLength: Int = 256) -> [Int] {
        let tokens = tokenize(text)
        let ids = convertTokensToIds(tokens)
        
        // Truncate if too long
        let truncated = Array(ids.prefix(maxLength - 1)) // Leave space for EOS
        
        // Add EOS token
        return truncated + [vocabulary[eosToken] ?? 2]
    }
    
    // MARK: - Helper Methods
    private func isSpecialToken(_ token: String) -> Bool {
        return [padToken, bosToken, eosToken, unkToken].contains(token)
    }
    
    /// Get vocabulary size
    var vocabularySize: Int {
        return vocabulary.count
    }
    
    /// Get special token IDs
    var specialTokenIds: [String: Int] {
        return [
            "pad": vocabulary[padToken] ?? 1,
            "bos": vocabulary[bosToken] ?? 0,
            "eos": vocabulary[eosToken] ?? 2,
            "unk": vocabulary[unkToken] ?? 3
        ]
    }
    
    /// Check if token exists in vocabulary
    func hasToken(_ token: String) -> Bool {
        return vocabulary[token] != nil
    }
}

// MARK: - Extensions
extension BARTTokenizer {
    /// Get vocabulary statistics
    func getVocabularyStats() -> [String: Any] {
        return [
            "total_tokens": vocabulary.count,
            "special_tokens": specialTokenIds.count,
            "has_config": !tokenizerConfig.isEmpty
        ]
    }
    
    /// Batch tokenize multiple texts
    func batchTokenize(_ texts: [String]) -> [[String]] {
        return texts.map { tokenize($0) }
    }
    
    /// Batch encode multiple texts
    func batchEncode(_ texts: [String], maxLength: Int = 256) -> [[Int]] {
        return texts.map { encode($0, maxLength: maxLength) }
    }
}
