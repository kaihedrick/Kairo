// filepath: BibleAppPOCV2/Services/TokenizerService.swift
import Foundation

/// Wraps BPE for normal text and injects special IDs from tokenizer_config.json.
/// This guarantees the model sees the exact IDs it was trained on.
struct TokenizerService {
    struct SpecialIds {
        let verseId: Int32
        let verseRefId: Int32
        let verseTextId: Int32
        let verseTagId: Int32
        let startCommentaryId: Int32
        let endCommentaryId: Int32
        let startDevotionalId: Int32
        let endDevotionalId: Int32
        let padId: Int32
    }

    private let bpe: GPT2BPEEncoder
    private let ids: SpecialIds

    init(bpe: GPT2BPEEncoder, ids: SpecialIds) {
        self.bpe = bpe
        self.ids = ids
    }

    /// Convert "Matthew 2:1" -> "MATTHEW_2_1"
    private func keyFromVerseRef(_ ref: String) -> String {
        // Very simple: uppercased, non-alnums to underscore, collapse repeats.
        let upper = ref.uppercased()
        let mapped = upper.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "_"
        }
        let s = String(mapped)
        // collapse multiple underscores
        let collapsed = s.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Build the full prompt as token IDs:
    /// [VERSE_ID] KEY  [VERSE_REF] "Matthew 2:1"  [VERSE_TEXT] <text>  [VERSE]  [START_COMMENTARY]
    func encodePrompt(verseRef: String, verseText: String, seqLen: Int) -> [Int32] {
        var out: [Int32] = []
        out.append(ids.verseId)
        out += bpe.encode(keyFromVerseRef(verseRef), maxLength: seqLen - out.count).map { Int32($0) }

        out.append(ids.verseRefId)
        out += bpe.encode(verseRef, maxLength: seqLen - out.count).map { Int32($0) }

        out.append(ids.verseTextId)
        out += bpe.encode(verseText, maxLength: seqLen - out.count).map { Int32($0) }

        out.append(ids.verseTagId)
        out.append(ids.startCommentaryId)

        // Clamp to seq len
        if out.count > seqLen { out = Array(out.prefix(seqLen)) }
        return out
    }

    var padId: Int32 { ids.padId }
    var startCommentaryId: Int32 { ids.startCommentaryId }
    var endCommentaryId: Int32 { ids.endCommentaryId }
    var startDevotionalId: Int32 { ids.startDevotionalId }
    var endDevotionalId: Int32 { ids.endDevotionalId }
}
