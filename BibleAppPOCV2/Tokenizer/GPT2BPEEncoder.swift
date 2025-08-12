// filepath: BibleAppPOCV2/Tokenizer/GPT2BPEEncoder.swift
import Foundation

/// Minimal GPT-2 BPE encoder. Loads vocab.json, merges.txt, and special token maps.
/// Produces token IDs matching Python when assets are identical.
final class GPT2BPEEncoder {
    static let shared = GPT2BPEEncoder()
    
    private let byteEncoder: [UInt8: String]
    private var bpeRanks: [Pair: Int]
    private var encoder: [String: Int]
    private var specialTokens: [String: Int]
    var vocabCount: Int { encoder.count }
    var isReady: Bool { encoder.count > 0 && bpeRanks.count > 0 }
    
    private init() {
        // Initialize with default values - will be loaded when needed
        self.byteEncoder = GPT2ByteEncoder.make()
        self.bpeRanks = [:]
        self.encoder = [:]
        self.specialTokens = [:]
        
        // Load tokenizer assets
        loadTokenizerAssets()
    }
    
    struct Pair: Hashable { let a: String; let b: String }
    
    func encode(_ text: String, maxLength: Int = 512) -> [Int] {
        // Split by special tokens to preserve them
        let allSpecials = specialTokens.keys.sorted { $0.count > $1.count }
        var tokens: [Int] = []
        var remaining = text

        func addEncodedPiece(_ piece: String) {
            // byte preprocess
            var transformed = ""
            for b in piece.utf8 { transformed += (byteEncoder[b] ?? String(UnicodeScalar(b))) }
            // whitespace tokenization using canonical GPT-2 regex with Unicode support
            let pattern = try! NSRegularExpression(
                pattern: #"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+"#,
                options: []
            )
            let ns = transformed as NSString
            let matches = pattern.matches(in: transformed, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                let word = ns.substring(with: m.range)
                let bpeTokens = bpe(word)
                for t in bpeTokens { if let id = encoder[t] { tokens.append(id) } }
            }
        }

        while !remaining.isEmpty {
            var matchedSpecial: String?
            for s in allSpecials {
                if remaining.hasPrefix(s) { matchedSpecial = s; break }
            }
            if let s = matchedSpecial, let id = specialTokens[s] {
                tokens.append(id)
                remaining.removeFirst(s.count)
            } else {
                // take next char until we hit a special
                if let idx = allSpecials.compactMap({ st in remaining.range(of: st)?.lowerBound }).min(by: { $0 < $1 }) {
                    let piece = String(remaining[..<idx])
                    addEncodedPiece(piece)
                    remaining = String(remaining[idx...])
                } else {
                    addEncodedPiece(remaining)
                    remaining.removeAll()
                }
            }
        }

        return Array(tokens.prefix(maxLength))
    }
    
    func decode(_ tokenIds: [Int]) -> String {
        // Simple reverse lookup - in a real implementation you'd want more sophisticated decoding
        let reverseVocab = Dictionary(uniqueKeysWithValues: encoder.map { ($1, $0) })
        let tokens = tokenIds.compactMap { reverseVocab[$0] }
        return tokens.joined(separator: "")
    }
    
    // Byte pair encoding for a single token-like string
    private func bpe(_ token: String) -> [String] {
        if token.isEmpty { return [] }
        var word: [String] = token.map { String($0) }
        var pairs = getPairs(word)
        if pairs.isEmpty { return [token] }
        while true {
            let rankedPairs = pairs.compactMap { (p: Pair) -> (Pair, Int)? in
                if let r = bpeRanks[p] { return (p, r) } else { return nil }
            }
            if rankedPairs.isEmpty { break }
            let (_, _) = rankedPairs.min(by: { $0.1 < $1.1 })!
            let best = rankedPairs.min(by: { $0.1 < $1.1 })!.0
            var newWord: [String] = []
            var i = 0
            while i < word.count {
                if i < word.count - 1, word[i] == best.a, word[i+1] == best.b {
                    newWord.append(best.a + best.b)
                    i += 2
                } else {
                    newWord.append(word[i])
                    i += 1
                }
            }
            word = newWord
            if word.count == 1 { break }
            pairs = getPairs(word)
        }
        return word
    }

    private func getPairs(_ word: [String]) -> Set<Pair> {
        var pairs: Set<Pair> = []
        for i in 0..<(word.count - 1) {
            pairs.insert(Pair(a: word[i], b: word[i+1]))
        }
        return pairs
    }
    
    // Format input for Bible commentary generation
    func formatInput(verseRef: String, verseText: String) -> String {
        let verseId = verseRef
            .uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")  // colon → underscore to match training
            .replacingOccurrences(of: "-", with: "_")   // if any
            .replacingOccurrences(of: "[^A-Z0-9_]+", with: "", options: .regularExpression)
        return """
        [VERSE_ID] \(verseId)
        [VERSE_REF] \(verseRef)
        [VERSE_TEXT] \(verseText)
        [VERSE]
        [START_COMMENTARY]
        """
    }
    
    private func loadTokenizerAssets() {
        // Try to load tokenizer assets from bundle
        
        if let vocabURL = BundleLoader.url(name: "vocab", ext: "json"),
           let mergesURL = BundleLoader.url(name: "merges", ext: "txt"),
           let specialURL = BundleLoader.url(name: "special_tokens_map", ext: "json"),
           let addedURL = BundleLoader.url(name: "added_tokens", ext: "json") {
            
            do {
                // Load vocab.json
                let vocabData = try Data(contentsOf: vocabURL)
                if let vocabDict = try JSONSerialization.jsonObject(with: vocabData) as? [String: Int] {
                    self.encoder = vocabDict
                    print("✅ BPE: Loaded vocab.json (\(vocabDict.count) tokens)")
                }
                
                // Load merges.txt
                let mergesText = try String(contentsOf: mergesURL)
                let lines = mergesText.split(separator: "\n").dropFirst() // skip header
                var ranks: [Pair: Int] = [:]
                for (i, line) in lines.enumerated() {
                    let parts = line.split(separator: " ")
                    if parts.count == 2 {
                        let p = Pair(a: String(parts[0]), b: String(parts[1]))
                        ranks[p] = i
                    }
                }
                self.bpeRanks = ranks
                print("✅ BPE: Loaded merges.txt (\(ranks.count) merges)")
                
                // Load special tokens
                var specials: [String: Int] = [:]
                if let data = try? Data(contentsOf: specialURL),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for (_, v) in dict {
                        if let inner = v as? [String: Any],
                           let token = inner["content"] as? String,
                           let id = inner["id"] as? Int {
                            specials[token] = id
                        }
                    }
                }
                
                if let data = try? Data(contentsOf: addedURL),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for item in arr {
                        if let token = item["content"] as? String, let id = item["id"] as? Int {
                            specials[token] = id
                        }
                    }
                }
                
                self.specialTokens = specials
                print("✅ BPE: Loaded special tokens (\(specials.count) tokens)")
                
            } catch {
                print("❌ BPE: Failed to load tokenizer assets: \(error)")
            }
        } else {
            print("⚠️ BPE: Tokenizer assets not found in bundle")
        }
    }
}
