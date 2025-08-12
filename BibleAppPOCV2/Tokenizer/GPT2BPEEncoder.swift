import Foundation

/// Minimal GPT-2 BPE encoder. Loads vocab.json, merges.txt, and special token maps.
/// Produces token IDs matching Python when assets are identical.
final class GPT2BPEEncoder {
    private let byteEncoder: [UInt8: String]
    private let bpeRanks: [Pair: Int]
    private let encoder: [String: Int]
    private let specialTokens: [String: Int]
    var vocabCount: Int { encoder.count }

    struct Pair: Hashable { let a: String; let b: String }

    init(vocabURL: URL, mergesURL: URL, specialTokensURL: URL?, addedTokensURL: URL?) throws {
        // Load vocab.json (token -> id)
        let vocabData = try Data(contentsOf: vocabURL)
        guard let vocabDict = try JSONSerialization.jsonObject(with: vocabData) as? [String: Int] else {
            throw NSError(domain: "GPT2BPEEncoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid vocab.json"])
        }
        self.encoder = vocabDict

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

        // Load special tokens
        var specials: [String: Int] = [:]
        if let specialTokensURL = specialTokensURL {
            if let data = try? Data(contentsOf: specialTokensURL),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Extract map values that are string->id
                for key in ["eos_token", "pad_token", "bos_token"] {
                    if let token = (dict[key] as? [String: Any])?["content"] as? String,
                       let id = (dict[key] as? [String: Any])?["id"] as? Int {
                        specials[token] = id
                    }
                }
                // Bible app specific tokens if present
                for (_, v) in dict {
                    if let inner = v as? [String: Any],
                       let token = inner["content"] as? String,
                       let id = inner["id"] as? Int {
                        specials[token] = id
                    }
                }
            }
        }
        if let addedTokensURL = addedTokensURL,
           let data = try? Data(contentsOf: addedTokensURL),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in arr {
                if let token = item["content"] as? String, let id = item["id"] as? Int {
                    specials[token] = id
                }
            }
        }
        self.specialTokens = specials

        // Byte encoder
        self.byteEncoder = GPT2ByteEncoder.make()
    }

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
}


