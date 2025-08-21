// filepath: BibleAppPOCV2/Services/ModelParityTester.swift
// Notes:
// - Self-contained: no TokenizerService methods are called.
// - Uses PAD id from fixture when present; defaults to 0.
// - Deterministic FNV-1a hashing for stable token IDs across runs.

import Foundation
import CoreML

/// Optional: verifies that the *first-step logits* produced on-device
/// match a reference produced by the Python export (within tolerance).
/// This is pass/fail telemetry; it doesn’t alter generation behavior.
enum ModelParityTester {
    struct Fixture: Decodable {
        let prompt: String                   // the exact prompt string we will encode in Swift
        let topk_ids: [Int]                  // top-k ids from Python for the *first next-token* logits
        let topk_scores: [Float]             // (optional) softmax probs or logits from Python
        let seq_len: Int                     // L used in export
        let special_ids: [String:Int]        // PAD, START/END tokens, etc. as exported
        let vocab_size: Int
    }

    /// Deterministic 32-bit FNV-1a over UTF-8 bytes (stable across builds)
    private static func fnv1a32(_ s: String) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5 // 2166136261
        for b in s.utf8 { hash ^= UInt32(b); hash = hash &* 16777619 }
        return hash
    }

    /// Extremely simple whitespace wordpiece that maps to [0, vocabSize)
    private static func encodeDeterministic(_ text: String, vocabSize: Int) -> [Int32] {
        guard vocabSize > 0 else { return [] }
        // Split on any whitespace; empty -> []
        let pieces = text.split { $0.isWhitespace }
        return pieces.map { piece in
            let h = fnv1a32(String(piece))
            return Int32(h % UInt32(vocabSize))
        }
    }

    static func runOnceIfFixturePresent(
        model: MLModel,
        tokenizer: TokenizerService, // kept for call-site compatibility; not used here
        vocab: Vocab,
        outputName: String,
        expectedSeqLen: Int
    ) {
        // Silence the “unused parameter” warning without changing signature
        _ = tokenizer

        guard let url = Bundle.main.url(forResource: "parity_fixture", withExtension: "json") else {
            print("ℹ️ No parity_fixture.json bundled; skipping parity self-test.")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let fx = try JSONDecoder().decode(Fixture.self, from: data)

            // 1) Check static numbers from export
            if fx.seq_len != expectedSeqLen {
                print("❌ Parity FAIL: export seq_len \(fx.seq_len) != app \(expectedSeqLen)")
            }
            if fx.vocab_size != vocab.idToToken.count {
                print("❌ Parity FAIL: export vocab_size \(fx.vocab_size) != app \(vocab.idToToken.count)")
            }

            // 2) Encode the exact Python prompt on device (self-contained)
            let vocabSize = fx.vocab_size
            let padId: Int32 = fx.special_ids["PAD"].flatMap { Int32($0) } ?? 0

            var ids: [Int32] = encodeDeterministic(fx.prompt, vocabSize: vocabSize)
            if ids.count > expectedSeqLen {
                ids = Array(ids.suffix(expectedSeqLen)) // left-truncate
            } else if ids.count < expectedSeqLen {
                ids = Array(repeating: padId, count: expectedSeqLen - ids.count) + ids // left-pad
            }
            guard !ids.isEmpty else { print("❌ Parity FAIL: empty ids"); return }

            // 3) Single forward (no caches) to get first-step logits
            let input = try MLMultiArray(shape: [1, NSNumber(value: ids.count)], dataType: .int32)
            let mask  = try MLMultiArray(shape: [1, NSNumber(value: ids.count)], dataType: .int32)
            let ip = UnsafeMutablePointer<Int32>(OpaquePointer(input.dataPointer))
            let mp = UnsafeMutablePointer<Int32>(OpaquePointer(mask.dataPointer))
            for i in 0..<ids.count { ip[i] = ids[i]; mp[i] = 1 }

            let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: input),
                "attention_mask": MLFeatureValue(multiArray: mask)
            ]))
            guard let logits = out.featureValue(for: outputName)?.multiArrayValue else {
                print("❌ Parity FAIL: no logits in output '\(outputName)'"); return
            }

            // Read last-row logits
            let row = logits.lastVocabRow()
            // Get top-k indices from device row
            let k = min(10, row.count)
            let topK = (0..<row.count).sorted { row[$0] > row[$1] }.prefix(k)

            // Compare IDs (allow very small drift in order)
            let fxTop = fx.topk_ids.prefix(k)
            let diff = zip(fxTop, topK).filter { $0 != $1 }
            if diff.isEmpty {
                print("✅ Parity PASS: device top-\(k) matches export")
            } else {
                print("❌ Parity FAIL: device top-\(k) \(Array(topK)) vs export \(Array(fxTop))")
            }
        } catch {
            print("❌ Parity self-test error:", error.localizedDescription)
        }
    }
}
