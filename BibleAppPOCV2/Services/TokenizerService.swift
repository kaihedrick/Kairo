// TokenizerService.swift
import Foundation

public struct TokenizerIDs { let verseId:Int32, verseRefId:Int32, verseTextId:Int32, verseTagId:Int32
    let startCommentaryId:Int32, endCommentaryId:Int32, startDevotionalId:Int32, endDevotionalId:Int32, padId:Int32 }

public final class TokenizerService {
    private let bpe: GPT2BPETokenizer
    private let ids: TokenizerIDs

    public init(art: TokenizerArtifacts) {
        self.bpe = GPT2BPETokenizer(vocab: art.tokenToId, merges: art.merges, idToToken: art.idToToken)
        func id(_ s:String) -> Int32 { Int32(art.addedTokens[s] ?? -1) }
        self.ids = TokenizerIDs(
            verseId: id("[VERSE]"), verseRefId: id("[VERSE_REF]"), verseTextId: id("[VERSE_TEXT]"), verseTagId: id("[VERSE_ID]"),
            startCommentaryId: id("[START_COMMENTARY]"), endCommentaryId: id("[END_COMMENTARY]"),
            startDevotionalId: id("[START_DEVOTIONAL]"), endDevotionalId: id("[END_DEVOTIONAL]"), padId: id("[PAD]")
        )
    }

    public func encodePrompt(verseRef: String, verseText: String, maxLen: Int) -> [Int32] {
        var out: [Int32] = []
        func push(_ x:Int32) { if x >= 0 { out.append(x) } }
        // structural header
        push(ids.verseTagId)
        out += bpe.encode(" \(verseRef.replacingOccurrences(of: ":", with: "_"))").map(Int32.init)
        push(ids.verseRefId)
        out += bpe.encode(" \(verseRef)").map(Int32.init)
        push(ids.verseTextId)
        out += bpe.encode(" \(verseText)").map(Int32.init)
        push(ids.verseId)
        push(ids.startCommentaryId)
        // trim to budget
        if out.count > maxLen { out = Array(out.prefix(maxLen)) }
        return out
    }

    public func decode(ids: [Int]) -> String {
        return bpe.decode(ids)
    }
}