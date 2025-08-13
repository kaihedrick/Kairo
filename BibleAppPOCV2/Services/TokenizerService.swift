// filepath: BibleAppPOCV2/Services/TokenizerService.swift
import Foundation

/// Wraps the real BPE and injects special IDs from tokenizer_config.json.
struct TokenizerService {
    struct SpecialIds {
        let verseId: Int32, verseRefId: Int32, verseTextId: Int32, verseTagId: Int32
        let startCommentaryId: Int32, endCommentaryId: Int32
        let startDevotionalId: Int32, endDevotionalId: Int32, padId: Int32
    }

    private let bpe: GPT2BPEEncoder
    private let ids: SpecialIds

    init(bpe: GPT2BPEEncoder, ids: SpecialIds) {
        self.bpe = bpe; self.ids = ids
    }

    /// Convert "Matthew 2:1" -> "MATTHEW_2_1"
    private func keyFromVerseRef(_ ref: String) -> String {
        let upper = ref.uppercased()
        let mapped = upper.map { ch -> Character in (ch.isLetter || ch.isNumber) ? ch : "_" }
        let s = String(mapped)
        return s.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    func formatInput(verseRef: String, verseText: String) -> String {
        """
        [VERSE_ID] \(keyFromVerseRef(verseRef))
        [VERSE_REF] \(verseRef)
        [VERSE_TEXT] \(verseText)
        [VERSE]
        [START_COMMENTARY]
        """
    }

    /// Encode prompt with BPE (max = seqLen).
    func encodePrompt(verseRef: String, verseText: String, seqLen: Int) -> [Int32] {
        let prompt = formatInput(verseRef: verseRef, verseText: verseText)
        let ids = bpe.encode(prompt, maxLength: seqLen).map(Int32.init)
        return ids.isEmpty ? [ids.isEmpty ? self.ids.padId : ids[0]] : ids
    }
}
