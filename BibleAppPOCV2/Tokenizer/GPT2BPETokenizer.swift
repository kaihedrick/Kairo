// GPT2BPETokenizer.swift
import Foundation

// Faithful GPT-2 byte<->unicode mapping (same math as OpenAI/HF)
fileprivate func bytesToUnicode() -> [UInt8: Character] {
    var bs = Array(33...126).map { UInt8($0) }
    bs += Array(161...172).map { UInt8($0) }
    bs += Array(174...255).map { UInt8($0) }
    var cs = bs.map { UInt32($0) }
    var n: UInt32 = 0
    for b in 0...255 where !bs.contains(UInt8(b)) {
        bs.append(UInt8(b)); cs.append(256 + n); n += 1
    }
    var map: [UInt8: Character] = [:]
    for (b, c) in zip(bs, cs) { if let scalar = UnicodeScalar(c) { map[b] = Character(scalar) } }
    return map
}

fileprivate let b2u = bytesToUnicode()
fileprivate let u2b: [Character: UInt8] = {
    var m: [Character:UInt8] = [:]
    for (k,v) in b2u { m[v] = k }
    return m
}()

public final class GPT2BPETokenizer {
    // ranks: pair -> rank index (lower = merge first)
    private let ranks: [Pair: Int]
    private let vocab: [String: Int]
    private let idToToken: [Int: String]
    private var cache: [String: [String]] = [:]

    public struct Pair: Hashable { let a: String; let b: String }

    public init(vocab: [String:Int], merges: [(String,String)], idToToken: [Int:String]) {
        self.vocab = vocab
        self.idToToken = idToToken
        var r: [Pair:Int] = [:]
        for (i, m) in merges.enumerated() { r[Pair(a: m.0, b: m.1)] = i }
        self.ranks = r
    }

    // Regex from GPT-2 (ICU):
    // ('s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+)
    private lazy var pattern: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "('s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+)")
    }()

    private func getPairs(_ symbols: [String]) -> Set<Pair> {
        var pairs = Set<Pair>()
        guard !symbols.isEmpty else { return pairs }
        var prev = symbols[0]
        for s in symbols.dropFirst() { pairs.insert(Pair(a: prev, b: s)); prev = s }
        return pairs
    }

    private func bpe(_ token: String) -> [String] {
        if let c = cache[token] { return c }
        var word = token.map { String($0) }
        var pairs = getPairs(word)
        if pairs.isEmpty { cache[token] = word; return word }
        while true {
            var minRank = Int.max; var bigram: Pair? = nil
            for p in pairs { if let r = ranks[p], r < minRank { minRank = r; bigram = p } }
            guard let merge = bigram else { break }
            var newWord: [String] = []
            var i = 0
            while i < word.count {
                if i < word.count - 1 && word[i] == merge.a && word[i+1] == merge.b {
                    newWord.append(merge.a + merge.b)
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
        cache[token] = word
        return word
    }

    public func encode(_ text: String) -> [Int] {
        // bytes -> unicode per GPT-2
        let bytes = [UInt8](text.utf8)
        let mapped = String(bytes.map { b2u[$0]! })
        // regex split and BPE each chunk
        let ns = mapped as NSString
        let matches = pattern.matches(in: mapped, range: NSRange(location: 0, length: ns.length))
        var ids: [Int] = []
        for m in matches {
            let piece = ns.substring(with: m.range)
            for token in bpe(piece) {
                if let id = vocab[token] { ids.append(id) }
            }
        }
        return ids
    }

    public func decode(_ ids: [Int]) -> String {
        // map ids -> token string, then unicode→bytes back
        var s = ""
        s.reserveCapacity(ids.count * 4)
        for id in ids {
            if let t = idToToken[id] { s.append(t) }
        }
        // unicode back to bytes
        var out = [UInt8]()
        out.reserveCapacity(s.count)
        for ch in s { if let b = u2b[ch] { out.append(b) } }
        return String(decoding: out, as: UTF8.self)
    }
}