// filepath: BibleAppPOCV2/Tokenizer/GPT2BPEEncoder.swift
import Foundation

/// Minimal pair
private struct Pair: Hashable { let a: String; let b: String }

/// GPT-2 Byte-level BPE encoder (loads vocab.json, merges.txt + special tokens)
final class GPT2BPEEncoder {
    static let shared = GPT2BPEEncoder()

    private(set) var vocabCount: Int = 0
    private var encoder: [String:Int] = [:]
    private var decoder: [Int:String] = [:]
    private var bpeRanks: [Pair:Int] = [:]
    private var byteEncoder: [UInt8:String] = [:]
    private var specialTokens: [String:Int] = [:]

    private init() { loadAssets() }

    // MARK: - Public

    /// Encode text using byte-level BPE.
    func encode(_ text: String, maxLength: Int) -> [Int] {
        guard !encoder.isEmpty, !bpeRanks.isEmpty else { return [] }
        let specialsSorted = specialTokens.keys.sorted { $0.count > $1.count } // longest first
        var tokens: [Int] = []
        var remaining = text

        func addTokenPieces(_ piece: String) {
            // bytes → unicode
            let bytes = Array(piece.utf8)
            var mapped = ""
            mapped.reserveCapacity(bytes.count)
            for b in bytes { mapped.append(contentsOf: byteEncoder[b] ?? String(UnicodeScalar(Int(b))!)) }

            // split into BPE tokens
            let parts = bpe(mapped)
            for p in parts {
                if let id = encoder[p] { tokens.append(id) }
            }
        }

        while !remaining.isEmpty {
            // Prefer special tokens
            if let s = specialsSorted.first(where: { remaining.hasPrefix($0) }),
               let id = specialTokens[s] {
                tokens.append(id)
                remaining.removeFirst(s.count)
                continue
            }
            // Next chunk until the next special or end
            if let idx = specialsSorted
                .compactMap({ remaining.range(of: $0)?.lowerBound })
                .min(by: { $0 < $1 }) {
                let piece = String(remaining[..<idx])
                addTokenPieces(piece)
                remaining = String(remaining[idx...])
            } else {
                addTokenPieces(remaining)
                remaining.removeAll()
            }
        }
        return Array(tokens.prefix(maxLength))
    }

    // MARK: - Loading

    private func loadAssets() {
        guard
            let vocabURL = BundleLoader.url(name: "vocab", ext: "json"),
            let mergesURL = BundleLoader.url(name: "merges", ext: "txt")
        else { print("⚠️ BPE: Tokenizer assets not found in bundle"); return }

        do {
            // byte encoder (bytes_to_unicode)
            self.byteEncoder = GPT2ByteEncoder.make()

            // vocab.json (token → id)
            let vocabData = try Data(contentsOf: vocabURL)
            if let vocabDict = try JSONSerialization.jsonObject(with: vocabData) as? [String:Int] {
                self.encoder = vocabDict
                self.decoder = Dictionary(uniqueKeysWithValues: vocabDict.map { ($0.value, $0.key) })
                self.vocabCount = vocabDict.count
                print("✅ BPE: Loaded vocab.json (\(vocabDict.count) tokens)")
            }

            // merges.txt
            let mergesText = try String(contentsOf: mergesURL)
            let lines = mergesText.split(separator: "\n").dropFirst()
            var ranks: [Pair:Int] = [:]
            for (i, line) in lines.enumerated() {
                let parts = line.split(separator: " ")
                if parts.count == 2 { ranks[Pair(a: String(parts[0]), b: String(parts[1]))] = i }
            }
            self.bpeRanks = ranks
            print("✅ BPE: Loaded merges.txt (\(ranks.count) merges)")

            // special tokens (two places)
            var specials: [String:Int] = [:]
            if let mapURL = BundleLoader.url(name: "special_tokens_map", ext: "json"),
               let data = try? Data(contentsOf: mapURL),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
                for (_, v) in dict {
                    if let inner = v as? [String:Any],
                       let token = inner["content"] as? String,
                       let id = inner["id"] as? Int {
                        specials[token] = id
                    }
                }
            }
            if let addURL = BundleLoader.url(name: "added_tokens", ext: "json"),
               let data = try? Data(contentsOf: addURL),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String:Any]] {
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
    }

    // MARK: - BPE core

    private func getPairs(_ word: [String]) -> Set<Pair> {
        guard word.count >= 2 else { return [] }
        var pairs: Set<Pair> = []
        for i in 0..<(word.count - 1) { pairs.insert(.init(a: word[i], b: word[i+1])) }
        return pairs
    }

    private func bpe(_ token: String) -> [String] {
        if token.isEmpty { return [] }
        var word: [String] = token.map { String($0) }
        var pairs = getPairs(word)
        if pairs.isEmpty { return [token] }

        while true {
            let rankedPairs = pairs.compactMap { p -> (Pair,Int)? in
                guard let r = bpeRanks[p] else { return nil }
                return (p, r)
            }
            if rankedPairs.isEmpty { break }
            let best = rankedPairs.min(by: { $0.1 < $1.1 })!.0

            var newWord: [String] = []
            var i = 0
            while i < word.count {
                if i < word.count - 1, word[i] == best.a, word[i+1] == best.b {
                    newWord.append(best.a + best.b)
                    i += 2
                } else {
                    newWord.append(word[i]); i += 1
                }
            }
            word = newWord
            if word.count == 1 { break }
            pairs = getPairs(word)
        }
        return word
    }
}
