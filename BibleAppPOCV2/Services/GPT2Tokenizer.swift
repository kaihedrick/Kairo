import Foundation

class GPT2Tokenizer {
    static let shared = GPT2Tokenizer()
    
    private var vocabulary: [String: Int] = [:]
    private var reverseVocabulary: [Int: String] = [:]
    private var merges: [String] = []
    
    // Special tokens from the model
    private let endOfTextToken = "<|endoftext|>"
    private let padToken = "[PAD]"
    private let verseIdToken = "[VERSE_ID]"
    private let verseRefToken = "[VERSE_REF]"
    private let verseTextToken = "[VERSE_TEXT]"
    private let verseToken = "[VERSE]"
    private let startCommentaryToken = "[START_COMMENTARY]"
    private let endCommentaryToken = "[END_COMMENTARY]"
    private let startDevotionalToken = "[START_DEVOTIONAL]"
    private let endDevotionalToken = "[END_DEVOTIONAL]"
    
    // Token IDs - Updated to match the expanded vocabulary (50266 tokens)
    private let endOfTextTokenId = 50256
    private let verseIdTokenId = 50257        // Bible special token
    private let verseRefTokenId = 50258       // Bible special token
    private let verseTextTokenId = 50259      // Bible special token
    private let verseTokenId = 50260          // Bible special token
    private let startCommentaryTokenId = 50261 // Bible special token
    private let endCommentaryTokenId = 50262   // Bible special token
    private let startDevotionalTokenId = 50263 // Bible special token
    private let endDevotionalTokenId = 50264  // Bible special token
    private let padTokenId = 50265            // Bible special token
    
    init() {
        loadVocabulary()
        loadMerges()
    }
    
    private func loadVocabulary() {
        print("📱 Loading full GPT-2 vocabulary from bundled files...")
        vocabulary = [:]
        if let vocabURL = BundleLoader.url(name: "vocab", ext: "json"),
           let vocabData = try? Data(contentsOf: vocabURL),
           let vocabDict = try? JSONSerialization.jsonObject(with: vocabData) as? [String: Int] {
            print("✅ Loaded base vocabulary with \(vocabDict.count) tokens from \(vocabURL.lastPathComponent)")
            vocabulary = vocabDict
        } else {
            // Placeholder mode: rely on special tokens only (encoding is handled by BPE when available)
            print("ℹ️ Placeholder tokenizer active (special tokens only).")
        }
        
        // Always ensure special tokens with correct IDs are present
        vocabulary[endOfTextToken] = endOfTextTokenId
        vocabulary[verseIdToken] = verseIdTokenId
        vocabulary[verseRefToken] = verseRefTokenId
        vocabulary[verseTextToken] = verseTextTokenId
        vocabulary[verseToken] = verseTokenId
        vocabulary[startCommentaryToken] = startCommentaryTokenId
        vocabulary[endCommentaryToken] = endCommentaryTokenId
        vocabulary[startDevotionalToken] = startDevotionalTokenId
        vocabulary[endDevotionalToken] = endDevotionalTokenId
        vocabulary[padToken] = padTokenId
        
        print("✅ Vocabulary initialized with \(vocabulary.count) entries (includes special tokens)")
        
        // Create reverse vocabulary
        reverseVocabulary = Dictionary(uniqueKeysWithValues: vocabulary.map { ($1, $0) })
    }
    
    private func loadMerges() {
        // Since we're using a .mlpackage file, we'll use a simplified approach
        // In a production app, you might want to bundle a merges file or use a different tokenization strategy
        print("📱 Using .mlpackage model - simplified merges approach")
        
        self.merges = []
        
        print("✅ Using simplified tokenization (no external merges file)")
    }
    
    func tokenize(_ text: String) -> [Int] {
        print("🔤 Tokenizing text: \(text.prefix(50))...")
        
        // Handle special tokens first
        var tokens: [Int] = []
        var remainingText = text
        
        // Check for special tokens in the text
        let specialTokens = [
            (startCommentaryToken, startCommentaryTokenId),
            (endCommentaryToken, endCommentaryTokenId),
            (startDevotionalToken, startDevotionalTokenId),
            (endDevotionalToken, endDevotionalTokenId),
            (verseIdToken, verseIdTokenId),
            (verseRefToken, verseRefTokenId),
            (verseTextToken, verseTextTokenId),
            (verseToken, verseTokenId),
            (padToken, padTokenId),
            (endOfTextToken, endOfTextTokenId)
        ]
        
        for (token, tokenId) in specialTokens {
            while let range = remainingText.range(of: token) {
                // Add tokens before the special token
                let beforeToken = String(remainingText[..<range.lowerBound])
                if !beforeToken.isEmpty {
                    tokens.append(contentsOf: tokenizeWords(beforeToken))
                }
                
                // Add the special token
                tokens.append(tokenId)
                
                // Remove the processed part
                remainingText = String(remainingText[range.upperBound...])
            }
        }
        
        // Tokenize remaining text
        if !remainingText.isEmpty {
            tokens.append(contentsOf: tokenizeWords(remainingText))
        }
        
        print("🔤 Tokenized to \(tokens.count) tokens: \(tokens.prefix(10))...")
        return tokens
    }
    
    private func tokenizeWords(_ text: String) -> [Int] {
        // Simple word-based tokenization for now
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var tokens: [Int] = []
        
        for word in words {
            if let tokenId = vocabulary[word] {
                tokens.append(tokenId)
            } else {
                let lowercased = word.lowercased()
                if let tokenId = vocabulary[lowercased] {
                    tokens.append(tokenId)
                } else {
                    // Unknown token fallback for placeholder mode
                    tokens.append(0)
                }
            }
        }
        
        return tokens
    }
    
    func detokenize(_ tokens: [Int]) -> String {
        print("🔤 Detokenizing \(tokens.count) tokens...")
        
        var text = ""
        for tokenId in tokens {
            if let token = reverseVocabulary[tokenId] {
                if token == endOfTextToken || token == padToken { continue }
                if !text.isEmpty && !token.hasPrefix("[") && !token.hasPrefix("<") {
                    text += " "
                }
                text += token
            } else {
                // Unknown token id; render as placeholder
                if !text.isEmpty { text += " " }
                text += "[token\(tokenId)]"
            }
        }
        
        print("🔤 Detokenized text: \(text.prefix(100))...")
        return text
    }
    
    func formatInput(verseRef: String, verseText: String) -> String {
        let verseId = verseRef
            .uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")  // colon → underscore to match training
            .replacingOccurrences(of: "-", with: "_")   // if any
            .replacingOccurrences(of: "[^A-Z0-9_]+", with: "", options: .regularExpression)
        return """
        \(verseIdToken) \(verseId)
        \(verseRefToken) \(verseRef)
        \(verseTextToken) \(verseText)
        \(verseToken)
        \(startCommentaryToken)
        """
    }
    
    // MARK: - Public Methods
    
    func encode(_ text: String, maxLength: Int = 512) -> [Int] {
        let tokens = tokenize(text)
        return Array(tokens.prefix(maxLength))
    }
    
    func decode(_ tokens: [Int]) -> String {
        return detokenize(tokens)
    }
    
    // MARK: - Special Token Access
    
    func getSpecialTokenId(for token: String) -> Int? {
        switch token {
        case startCommentaryToken: return startCommentaryTokenId
        case endCommentaryToken: return endCommentaryTokenId
        case startDevotionalToken: return startDevotionalTokenId
        case endDevotionalToken: return endDevotionalTokenId
        case verseIdToken: return verseIdTokenId
        case verseRefToken: return verseRefTokenId
        case verseTextToken: return verseTextTokenId
        case verseToken: return verseTokenId
        case padToken: return padTokenId
        case endOfTextToken: return endOfTextTokenId
        default: return nil
        }
    }
    
    var vocabularySize: Int {
        return vocabulary.count
    }
}
