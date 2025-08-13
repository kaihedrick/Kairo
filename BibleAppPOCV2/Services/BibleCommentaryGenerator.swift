// filepath: BibleAppPOCV2/Services/BibleCommentaryGenerator.swift
import Foundation
import CoreML
import SwiftUI

// Keep the enum tiny and local.
enum InferenceMode { case coreml, fallback }

/// Minimal half→float for reading f16 logits quickly
@inline(__always) private func f16to32(_ h: UInt16) -> Float {
    let s = (h & 0x8000) != 0
    let e = Int((h & 0x7C00) >> 10)
    var f = Int(h & 0x03FF)
    let val: Float
    if e == 0 {
        if f == 0 { val = 0 }
        else {
            var exp = -14
            while (f & 0x400) == 0 { f <<= 1; exp -= 1 }
            f &= 0x3FF
            val = ldexpf(Float(f) / 1024 + 1, Int32(exp))
        }
    } else if e == 31 { val = .infinity }
    else { val = ldexpf(Float(f) / 1024 + 1, Int32(e - 15)) }
    return s ? -val : val
}

@MainActor
final class BibleCommentaryGenerator: ObservableObject {
    static let shared = BibleCommentaryGenerator()
    private static var didInit = false

    // UI state
    @Published var isGenerating = false
    @Published var generatedText = ""
    @Published var error: String?
    @Published private(set) var mode: InferenceMode = .fallback
    @Published private(set) var isReady = false

    // Core pieces
    private(set) var model: MLModel?
    private var vocab: Vocab?
    private var bpe: GPT2BPEEncoder?
    private(set) var outputName: String = "logits"

    // Generation knobs (mild defaults for quality)
    private let MAX_NEW: Int = 800
    private let REP_PENALTY: Float = 1.15
    private let TOP_K: Int = 100
    private let TOP_P: Float = 0.95
    private let TEMPERATURE: Float = 0.9

    // Export-driven constants
    private var seqLen: Int = 512
    private let exportedVocabSize: Int = 50266

    // Special IDs (populated from tokenizer_config.json)
    private var padId: Int32 = 50265
    private var startCommentaryId: Int32 = 50261
    private var endCommentaryId: Int32 = 50262
    private var startDevotionalId: Int32 = 50263
    private var endDevotionalId: Int32 = 50264
    private var verseId: Int32 = 50257
    private var verseRefId: Int32 = 50258
    private var verseTextId: Int32 = 50259
    private var verseTagId: Int32 = 50260

    private init() {
        if !Self.didInit {
            Self.didInit = true
            loadResources()
        }
    }

    // MARK: - Startup

    private func loadResources() {
        print("🚀 Starting resource loading…")

        // 1) Vocab + BPE
        do {
            self.vocab = try Vocab.loadBestFromBundle()
            if let v = vocab {
                print("✅ Vocab loaded (\(v.idToToken.count) entries)")
                assert(v.idToToken.count == exportedVocabSize, "Vocab size mismatch: expected \(exportedVocabSize)")
            }
        } catch {
            print("❌ Vocab load error: \(error.localizedDescription)")
        }

        self.bpe = GPT2BPEEncoder.shared
        print("✅ BPE ready (vocab: \(bpe?.vocabCount ?? 0))")

        // 2) Parse export report for seq_len
        parseExportReport()

        // 3) Special token IDs
        loadSpecialIdsFromTokenizerConfig()

        // 4) Load model
        loadModel()

        // Ready?
        isReady = (model != nil && vocab != nil && bpe != nil)
        mode = isReady ? .coreml : .fallback
        print(isReady ? "🟢 Core ML ready" : "⚠️ Fallback mode")
    }

    private func parseExportReport() {
        guard let url = Bundle.main.url(forResource: "export_report", withExtension: "json") else { return }
        do {
            let data = try Data(contentsOf: url)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let vs = obj["vocab_size"] as? Int { print("ℹ️ export_report vocab_size=\(vs)") }
                if let io = obj["model_io"] as? [String: Any], let L = io["seq_len"] as? Int {
                    seqLen = L
                } else if let L = obj["seq_len"] as? Int {
                    seqLen = L
                }
                print("✅ Sequence length set to \(seqLen)")
            }
        } catch {
            print("⚠️ export_report parse error: \(error.localizedDescription)")
        }
    }

    private func loadSpecialIdsFromTokenizerConfig() {
        guard let url = Bundle.main.url(forResource: "tokenizer_config", withExtension: "json") else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let cfg = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dec = cfg["added_tokens_decoder"] as? [String: [String: Any]] else { return }
            for (k, v) in dec {
                guard let id = Int32(k), let content = v["content"] as? String else { continue }
                switch content {
                case "[PAD]": padId = id
                case "[VERSE_ID]": verseId = id
                case "[VERSE_REF]": verseRefId = id
                case "[VERSE_TEXT]": verseTextId = id
                case "[VERSE]": verseTagId = id
                case "[START_COMMENTARY]": startCommentaryId = id
                case "[END_COMMENTARY]": endCommentaryId = id
                case "[START_DEVOTIONAL]": startDevotionalId = id
                case "[END_DEVOTIONAL]": endDevotionalId = id
                default: break
                }
            }
            print("✅ Special token IDs loaded (PAD=\(padId))")
        } catch {
            print("⚠️ tokenizer_config parse error: \(error.localizedDescription)")
        }
    }

    private func loadModel() {
        do {
            let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
            cfg.computeUnits = .cpuOnly               // simulator: CPU only
#else
            cfg.computeUnits = .cpuAndNeuralEngine    // device: ANE if possible
#endif
            if let gen = try? bible_commentary_model(configuration: cfg) {
                model = gen.model
                outputName = "logits"
                print("🟢 Loaded generated class")
                return
            }
            if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodelc") ??
                         Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage") {
                model = try MLModel(contentsOf: url, configuration: cfg)
                outputName = "logits"
                print("🟢 Loaded model from bundle")
                return
            }
            print("❌ No Core ML model found")
        } catch {
            print("❌ Model load error: \(error.localizedDescription)")
        }
    }

    // MARK: - Encoding

    /// Formats the prompt and encodes with GPT-2 BPE.
    private func encodePrompt(verseRef: String, verseText: String) -> [Int32] {
        guard let bpe = bpe else { return [] }
        // Format matches training:
        // [VERSE_ID] BOOK_CHAPTER_VERSE
        // [VERSE_REF] <ref>
        // [VERSE_TEXT] <text>
        // [VERSE]
        // [START_COMMENTARY]
        let bookRef = verseRef.replacingOccurrences(of: " ", with: "_").uppercased()
        let prompt =
        """
        [VERSE_ID] \(bookRef)
        [VERSE_REF] \(verseRef)
        [VERSE_TEXT] \(verseText)
        [VERSE]
        [START_COMMENTARY]
        """
        let ids = bpe.encode(prompt, maxLength: seqLen)
        return ids.map { Int32($0) }
    }

    // MARK: - Generation

    @MainActor
    func generateCommentary(for verseRef: String, verseText: String) async -> String {
        guard let model, let vocab else {
            error = "Model/vocab not loaded"; return ""
        }
        isGenerating = true
        error = nil
        generatedText = ""

        // Build input ids + attention mask
        var ids = encodePrompt(verseRef: verseRef, verseText: verseText)
        if ids.isEmpty { isGenerating = false; return "" }
        ids = Array(ids.prefix(seqLen))

        var attn = [Int32](repeating: 0, count: seqLen)
        for i in 0..<ids.count { attn[i] = 1 }

        var produced = 0
        var stop = false

        while produced < MAX_NEW && !stop && ids.count < seqLen {
            // 1) Prepare full-length inputs (simple, robust; works on simulator too)
            let inputIds = try? makeInt32Array([1, seqLen], fill: padId)
            let mask     = try? makeInt32Array([1, seqLen], fill: 0)
            if let inputIds, let mask {
                // copy current state
                let baseI = UnsafeMutablePointer<Int32>(OpaquePointer(inputIds.dataPointer))
                let baseM = UnsafeMutablePointer<Int32>(OpaquePointer(mask.dataPointer))
                for i in 0..<ids.count { baseI[i] = ids[i]; baseM[i] = 1 }

                // 2) Run once
                let provider = try? MLDictionaryFeatureProvider(dictionary: [
                    "input_ids": MLFeatureValue(multiArray: inputIds),
                    "attention_mask": MLFeatureValue(multiArray: mask)
                ])
                guard let provider,
                      let out = try? model.prediction(from: provider),
                      let logits = out.featureValue(for: outputName)?.multiArrayValue
                else {
                    error = "Model prediction failed"
                    break
                }

                // 3) Read last-step logits row and sample next id
                let row = readLogitsRow(logits)
                let next = sample(
                    logits: row,
                    recent: ids.suffix(64),
                    topK: TOP_K,
                    topP: TOP_P,
                    temperature: TEMPERATURE,
                    repPenalty: REP_PENALTY,
                    padId: padId
                )

                ids.append(next)
                produced += 1
                stop = (next == endDevotionalId)

                // 4) Stream every few tokens to keep the UI responsive
                if produced % 8 == 0 || stop {
                    let partial = vocab.decode(ids: ids)
                    self.generatedText = partial
                }
            } else {
                error = "Failed to allocate MLMultiArray buffers"
                break
            }
        }

        let text = vocab.decode(ids: ids)
        self.generatedText = text
        self.isGenerating = false
        return text
    }

    // MARK: - Sampling + helpers

    private func softmax(_ x: inout [Float]) {
        let m = x.max() ?? 0
        var s: Float = 0
        for i in 0..<x.count { x[i] = expf(x[i] - m); s += x[i] }
        if s > 0 { for i in 0..<x.count { x[i] /= s } }
    }

    private func sample(
        logits: [Float],
        recent: ArraySlice<Int32>,
        topK: Int,
        topP: Float,
        temperature: Float,
        repPenalty: Float,
        padId: Int32
    ) -> Int32 {
        var log = logits
        let n = log.count

        // Mask PAD
        if Int(padId) < n { log[Int(padId)] = -.infinity }

        // Light repetition penalty
        if repPenalty > 1 {
            for id in recent {
                let i = Int(id)
                if i >= 0 && i < n, log[i].isFinite {
                    log[i] /= repPenalty
                }
            }
        }

        // Temperature
        if temperature > 0 && temperature != 1 {
            for i in 0..<n { log[i] /= temperature }
        }

        // Top-k
        if topK > 0 && topK < n {
            let thr = log.enumerated().sorted(by: { $0.element > $1.element })[topK-1].element
            for i in 0..<n where log[i] < thr { log[i] = -.infinity }
        }

        // Top-p (nucleus)
        var probs = log
        softmax(&probs)
        let sorted = probs.enumerated().sorted { $0.element > $1.element }
        var cum: Float = 0
        var keep = Set<Int>()
        for (i, p) in sorted {
            cum += p; keep.insert(i)
            if cum >= topP { break }
        }
        for i in 0..<n where !keep.contains(i) { log[i] = -.infinity }

        // Greedy among survivors
        let argmax = (0..<n).max(by: { log[$0] < log[$1] }) ?? 0
        return Int32(argmax)
    }

    /// Safe reader for logits last row: supports [1, vocab] / [1, 1, vocab] and f16/f32.
    private func readLogitsRow(_ logits: MLMultiArray) -> [Float] {
        let shape = logits.shape.map { $0.intValue }
        let v = shape.last ?? logits.count
        switch logits.dataType {
        case .float32:
            let base = logits.dataPointer.bindMemory(to: Float.self, capacity: logits.count)
            return Array(UnsafeBufferPointer(start: base.advanced(by: logits.count - v), count: v))
        case .float16:
            let src = logits.dataPointer.bindMemory(to: UInt16.self, capacity: logits.count)
            var out = [Float](repeating: 0, count: v)
            let offset = logits.count - v
            for i in 0..<v { out[i] = f16to32(src[offset + i]) }
            return out
        default:
            fatalError("Unsupported logits dtype \(logits.dataType)")
        }
    }

    private func makeInt32Array(_ shape: [Int], fill: Int32 = 0) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .int32)
        let total = shape.reduce(1, *)
        let base = UnsafeMutablePointer<Int32>(OpaquePointer(arr.dataPointer))
        base.initialize(repeating: fill, count: total)
        return arr
    }
}

// MARK: - Commentary/Devotional Split (unchanged API)

struct ParsedBibleContent {
    let commentary: String
    let devotional: String
    let rawText: String

    init(commentary: String, devotional: String, rawText: String) {
        self.commentary = commentary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.devotional = devotional.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawText = rawText
    }
}

extension BibleCommentaryGenerator {
    func parseGeneratedContent(_ text: String) -> ParsedBibleContent {
        var commentary = ""
        var devotional = ""

        if let s = text.range(of: "[START_COMMENTARY]"),
           let e = text.range(of: "[END_COMMENTARY]"),
           s.upperBound < e.lowerBound {
            commentary = String(text[s.upperBound..<e.lowerBound])
        }

        if let s = text.range(of: "[START_DEVOTIONAL]"),
           let e = text.range(of: "[END_DEVOTIONAL]"),
           s.upperBound < e.lowerBound {
            devotional = String(text[s.upperBound..<e.lowerBound])
        }

        if commentary.isEmpty && devotional.isEmpty { commentary = text }

        func clean(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
             .replacingOccurrences(of: "\n\n\n", with: "\n\n")
             .replacingOccurrences(of: "  ", with: " ")
        }

        return ParsedBibleContent(
            commentary: clean(commentary),
            devotional: clean(devotional),
            rawText: text
        )
    }

    @MainActor
    func generateCommentaryAndDevotional(for verseRef: String, verseText: String) async -> ParsedBibleContent {
        let raw = await generateCommentary(for: verseRef, verseText: verseText)
        return parseGeneratedContent(raw)
    }
}
