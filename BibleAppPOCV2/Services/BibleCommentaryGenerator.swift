// filepath: BibleAppPOCV2/Services/BibleCommentaryGenerator.swift
import Foundation
import CoreML
import SwiftUI
import Accelerate

enum InferenceMode { case coreml, fallback }

@MainActor
final class BibleCommentaryGenerator: ObservableObject {
    static let shared = BibleCommentaryGenerator()
    private static var didInit = false

    @Published var isGenerating = false
    @Published var generatedText = ""
    @Published var error: String?
    @Published private(set) var mode: InferenceMode = .fallback
    @Published private(set) var isReady = false

    private(set) var model: MLModel?
    private var vocab: Vocab?
    private var bpe: GPT2BPEEncoder?
    private var tokenizerSvc: TokenizerService?
    private(set) var outputName: String = "logits"

    // ===== generation controls =====
    // Fast default: greedy on simulator (CPU only), mild sampling on device (ANE)
#if targetEnvironment(simulator)
    var temperature: Float? = nil   // greedy
    var topK: Int? = nil
    var topP: Float? = nil
#else
    var temperature: Float? = 0.8
    var topK: Int? = 60
    var topP: Float? = nil // avoid full-vocab sort
#endif
    var repetitionPenalty: Float = 1.10

    // --- Generation controls (tuneable) ---
    private let windowSize = 192               // reduces per-step compute (much faster than 512)
    private let noRepeatNGram = 3              // strong tri-gram block stops "Matthew Matthew ..."
    private let minTokensBeforeTransition = 140// when to start biasing to [END_COMMENTARY] -> [START_DEVOTIONAL]
    private let maxNewTokens = 384             // upper bound for new tokens

    // ===== model/tokenizer constants =====
    private var seqLen: Int = 512        // from export_report.json
    private let exportedVocabSize = 50266 // guide: 50266. used for checks only. :contentReference[oaicite:3]{index=3}

    // special ids (filled from tokenizer_config.json)
    private var padId: Int32 = 50265
    private var startCommentaryId: Int32 = 50261
    private var endCommentaryId: Int32 = 50262
    private var startDevotionalId: Int32 = 50263
    private var endDevotionalId: Int32 = 50264
    private var verseId: Int32 = 50257
    private var verseRefId: Int32 = 50258
    private var verseTextId: Int32 = 50259
    private var verseTagId: Int32 = 50260

    // Cached token IDs for guidance (optional if not found)
    private var _cachedMatthew: Int32?
    private var _cachedMark: Int32?
    private var _cachedLuke: Int32?
    private var _cachedJohn: Int32?

    private var loadTask: Task<Void, Error>?

    private init() {
        if !Self.didInit {
            Self.didInit = true
            loadResources()
        }
    }

    // ========== startup ==========

    private func loadResources() {
        print("🚀 Starting resource loading...")

        // 1) load vocab & BPE files used for decoding/encoding
        loadVocab()
        loadBPE()

        // 2) parse export report for seq_len and sanity
        parseExportReport()

        // 3) read special ids from tokenizer_config.json
        loadSpecialIdsFromTokenizerConfig()

        // 4) init tokenizer service (uses IDs + BPE)
        if let bpe = self.bpe {
            tokenizerSvc = TokenizerService(
                bpe: bpe,
                ids: .init(verseId: verseId, verseRefId: verseRefId, verseTextId: verseTextId, verseTagId: verseTagId,
                           startCommentaryId: startCommentaryId, endCommentaryId: endCommentaryId,
                           startDevotionalId: startDevotionalId, endDevotionalId: endDevotionalId, padId: padId)
            )
        }

        // 5) load model (inputs/outputs per guide) :contentReference[oaicite:4]{index=4}
        loadModel()

        // 6) finalize
        isReady = (model != nil && vocab != nil && tokenizerSvc != nil)
        mode = isReady ? .coreml : .fallback
        if isReady {
            NotificationCenter.default.post(name: .coreMLBibleModelReady, object: nil)
            print("🟢 Core ML Bible model ready")
        } else {
            print("⚠️ Fallback mode")
        }
    }

    private func loadVocab() {
        guard let url = Bundle.main.url(forResource: "id_to_token", withExtension: "json") else {
            print("❌ id_to_token.json missing"); return
        }
        do {
            vocab = try Vocab.load(from: url)
            if let v = vocab {
                print("✅ Vocab loaded (\(v.idToToken.count))")
                if v.idToToken.count != exportedVocabSize {
                    print("⚠️ Vocab count != exported size (\(exportedVocabSize))")
                }
                
                // Cache useful ids for guidance (optional if not found)
                _cachedMatthew = v.id(forToken: "ĠMatthew")
                _cachedMark = v.id(forToken: "ĠMark")
                _cachedLuke = v.id(forToken: "ĠLuke")
                _cachedJohn = v.id(forToken: "ĠJohn")
            }
        } catch { print("❌ Vocab load error:", error.localizedDescription) }
    }

    private func loadBPE() {
        // your GPT2ByteDecoder.swift + tokenizer assets must be in app bundle
        // BPE encoder should already load vocab.json + merges.txt
        bpe = GPT2BPEEncoder.shared
        print("✅ BPE ready (vocab: \(bpe?.vocabCount ?? 0))")
    }

    private func parseExportReport() {
        guard let url = Bundle.main.url(forResource: "export_report", withExtension: "json") else { return }
        do {
            let data = try Data(contentsOf: url)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let vs = obj["vocab_size"] as? Int { print("✅ Vocab size (export): \(vs)") }
                if let io = obj["model_io"] as? [String: Any], let L = io["seq_len"] as? Int {
                    seqLen = L
                } else if let L = obj["seq_len"] as? Int {
                    seqLen = L
                }
                print("✅ Sequence length: \(seqLen)")
            }
        } catch { print("⚠️ export_report parse error:", error.localizedDescription) }
    }

    private func loadSpecialIdsFromTokenizerConfig() {
        guard let url = Bundle.main.url(forResource: "tokenizer_config", withExtension: "json") else { return }
        do {
            let data = try Data(contentsOf: url)
            if let cfg = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dec = cfg["added_tokens_decoder"] as? [String: [String: Any]] {
                for (k, v) in dec {
                    guard let id = Int32(k), let content = v["content"] as? String else { continue }
                    switch content {
                    case "[VERSE_ID]": verseId = id
                    case "[VERSE_REF]": verseRefId = id
                    case "[VERSE_TEXT]": verseTextId = id
                    case "[VERSE]": verseTagId = id
                    case "[START_COMMENTARY]": startCommentaryId = id
                    case "[END_COMMENTARY]": endCommentaryId = id
                    case "[START_DEVOTIONAL]": startDevotionalId = id
                    case "[END_DEVOTIONAL]": endDevotionalId = id
                    case "[PAD]": padId = id
                    default: break
                    }
                }
                print("✅ Special IDs loaded (PAD=\(padId))")
            }
        } catch { print("⚠️ tokenizer_config parse error:", error.localizedDescription) }
    }

    private func loadModel() {
        do {
            let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
            cfg.computeUnits = .cpuOnly   // Simulator = CPU, slow (expected)
#else
            cfg.computeUnits = .cpuAndNeuralEngine
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
                print("🟢 Loaded mlmodel from bundle")
            }
        } catch {
            print("❌ Model load error:", error.localizedDescription)
        }
    }

    // ========== generation ==========

    /// Primary API
    func generateCommentary(for verseRef: String, verseText: String) async -> String {
        guard !isGenerating else { return generatedText }
        guard let model, let vocab, let tokenizerSvc else {
            error = "Model/tokenizer not ready"; return ""
        }

        isGenerating = true
        error = nil
        generatedText = ""

        // Build tokenized prompt as IDs (no raw "[TOKEN]" strings)
        let promptIds = tokenizerSvc.encodePrompt(verseRef: verseRef, verseText: verseText, seqLen: seqLen)

        // Allocate sequence state
        let L = seqLen
        var ids = [Int32](repeating: tokenizerSvc.padId, count: L)
        var mask = [Int32](repeating: 0, count: L)

        let prefix = min(promptIds.count, L)
        for i in 0..<prefix { ids[i] = promptIds[i]; mask[i] = 1 }

        var t = prefix



        // Pre-allocate Core ML arrays once
        let inputIds = try? MLMultiArray(shape: [1, NSNumber(value: L)], dataType: .int32)
        let attnMask = try? MLMultiArray(shape: [1, NSNumber(value: L)], dataType: .int32)
        /// Copy last `windowSize` tokens into buffers at positions [0..len-1], pad the rest.
        func fillBuffers(
            ids fullIds: [Int32],
            mask fullMask: [Int32],
            currentLen: Int,
            seqLen: Int,
            input: MLMultiArray,
            attn: MLMultiArray
        ) {
            let start = max(0, currentLen - windowSize)
            let len   = min(windowSize, currentLen) // how many "real" tokens we're sending now

            let pIds  = UnsafeMutablePointer<Int32>(OpaquePointer(input.dataPointer))
            let pMask = UnsafeMutablePointer<Int32>(OpaquePointer(attn.dataPointer))

            // Copy the visible slice into the *front* of the arrays (positions 0..len-1)
            if len > 0 {
                (0..<len).forEach { i in
                    pIds[i]  = fullIds[start + i]
                    pMask[i] = 1
                }
            }

            // Right-pad the rest with PAD / 0
            if len < seqLen {
                // pad ids
                pIds.advanced(by: len).initialize(repeating: padId, count: seqLen - len)
                // pad mask
                pMask.advanced(by: len).initialize(repeating: 0,    count: seqLen - len)
            }
        }

        // simple softmax over a small candidate set
        @inline(__always) func softmax(_ x: inout [Float]) {
            let m = x.max() ?? 0
            var s: Float = 0
            for i in 0..<x.count { x[i] = expf(x[i] - m); s += x[i] }
            if s > 0 { for i in 0..<x.count { x[i] /= s } }
        }

        // O(V) single pass to keep topK indices without sorting entire vocab
        func topKCandidates(_ row: UnsafeBufferPointer<Float>, k: Int) -> [Int] {
            if k <= 0 { return Array(0..<row.count) }    // greedy/temperature only
            var best: [(i: Int, v: Float)] = []
            best.reserveCapacity(k)
            for i in 0..<row.count {
                let v = row[i]
                if best.count < k { best.append((i, v)); best.sort { $0.v > $1.v } }
                else if v > best.last!.v { best.removeLast(); best.append((i, v)); best.sort { $0.v > $1.v } }
            }
            return best.map { $0.i }
        }
        
        /// Applies masks/penalties and samples the next token greedily among survivors.
        func sampleNextToken(
            from row: [Float],
            vocab: Int,
            step: Int,
            recentTokens: [Int32],
            generatedSoFar: Int
        ) -> Int32 {
            var logits = row
            let count  = min(vocab, logits.count)

            // 1) Hard masks: PAD should never be produced
            if padId >= 0 && Int(padId) < count { logits[Int(padId)] = -.infinity }

            // 2) No-repeat tri-gram
            if recentTokens.count >= noRepeatNGram - 1 {
                var seen: [ArraySlice<Int32>: Set<Int32>] = [:]
                let n = noRepeatNGram
                for i in 0..<(recentTokens.count - (n - 1)) {
                    let prefix = recentTokens[i..<(i + n - 1)]
                    let next   = recentTokens[i + n - 1]
                    seen[prefix, default: []].insert(next)
                }
                let currentPrefix = recentTokens.suffix(n - 1)
                if let forbid = seen[currentPrefix] {
                    for id in forbid { let i = Int(id); if i >= 0 && i < count { logits[i] = -.infinity } }
                }
            }

            // 3) Short-window repetition penalty (last 64 tokens)
            if repetitionPenalty > 1.0, !recentTokens.isEmpty {
                for id in recentTokens.suffix(64) {
                    let i = Int(id)
                    if i >= 0 && i < count, logits[i].isFinite {
                        logits[i] /= repetitionPenalty
                    }
                }
            }

            // 4) Light dampening of Gospel book tokens in early steps
            if generatedSoFar < 64 {
                for t in [_cachedMatthew, _cachedMark, _cachedLuke, _cachedJohn].compactMap({ $0 }) {
                    let i = Int(t)
                    if i >= 0 && i < count, logits[i].isFinite {
                        logits[i] *= 0.85 // 15% downweight so we don't loop on them
                    }
                }
            }

            // 5) Transition guidance after we've written a while:
            //    nudge toward [END_COMMENTARY] then [START_DEVOTIONAL].
            if generatedSoFar >= minTokensBeforeTransition {
                // tiny bias for [END_COMMENTARY]
                let endComm = Int(endCommentaryId)
                if endComm >= 0 && endComm < count, logits[endComm].isFinite {
                    logits[endComm] += 0.80 // small push
                }
                // if we just emitted [END_COMMENTARY], bias next to [START_DEVOTIONAL]
                if recentTokens.last == endCommentaryId {
                    let startDevo = Int(startDevotionalId)
                    if startDevo >= 0 && startDevo < count, logits[startDevo].isFinite {
                        logits[startDevo] += 1.10
                    }
                }
            }

            // 6) Temperature / Top-k / Top-p
            if let t = temperature, t > 0, t != 1 { for i in 0..<count { logits[i] /= t } }
            if let k = topK, k > 0 && k < count {
                let threshold = logits.enumerated().sorted { $0.element > $1.element }[k - 1].element
                for i in 0..<count where logits[i] < threshold { logits[i] = -.infinity }
            }
            if let p = topP, p < 1.0 {
                let m = logits.prefix(count).max() ?? 0
                var exps = logits.prefix(count).map { expf($0 - m) }
                let total = exps.reduce(0, +)
                if total > 0 {
                    for i in 0..<count { exps[i] /= total }
                    let sorted = exps.enumerated().sorted { $0.element > $1.element }
                    var keep = Set<Int>(); var cum: Float = 0
                    for (i,e) in sorted { cum += e; keep.insert(i); if cum >= p { break } }
                    for i in 0..<count where !keep.contains(i) { logits[i] = -.infinity }
                }
            }

            // 7) Greedy among survivors
            let best = (0..<count).max(by: { logits[$0] < logits[$1] }) ?? 0
            return Int32(best)
        }

        do {
            while t < L && (t - prefix) < maxNewTokens {
                // 1) Fill buffers with a sliding context window (much faster)
                fillBuffers(
                    ids: ids,
                    mask: mask,
                    currentLen: t,
                    seqLen: L,
                    input: inputIds!,
                    attn: attnMask!
                )

                // 2) Predict
                let provider = try MLDictionaryFeatureProvider(dictionary: [
                    "input_ids": MLFeatureValue(multiArray: inputIds!),
                    "attention_mask": MLFeatureValue(multiArray: attnMask!)
                ])
                let out = try await model.prediction(from: provider)

                // 3) Read logits and sample
                guard let logitsArray = out.featureValue(for: outputName)?.multiArrayValue else {
                    print("❌ No logits in output"); break
                }
                let shape = logitsArray.shape.map { $0.intValue }
                let vsize = shape.last ?? exportedVocabSize
                let rowPtr = logitsArray.rowAsFloat(atTime: t - 1, vocab: vsize)
                let row = Array(rowPtr)

                // IMPORTANT: recent tokens are the same slice we fed in
                let recentStart = max(0, t - windowSize)
                let recent = Array(ids[recentStart..<t])

                let next = sampleNextToken(
                    from: row, vocab: vsize, step: t - prefix,
                    recentTokens: recent, generatedSoFar: t - prefix
                )

                // Stop on any end-token
                if next == endDevotionalId || next == endCommentaryId {
                    ids[t] = next
                    mask[t] = 1
                    t += 1
                    print("🏁 Hit end token \(next).")
                    break
                }

                // 6) append/update
                ids[t] = next
                mask[t] = 1
                t += 1



                // incremental UI (cheap)
                if let vocab = self.vocab, (t - prefix) % 8 == 0 {
                    self.generatedText = vocab.decode(ids: Array(ids.prefix(t)))
                }
            }

            let final = vocab.decode(ids: Array(ids.prefix(t)))
            self.generatedText = final
            self.isGenerating = false
            return final
        } catch {
            self.error = error.localizedDescription
            self.isGenerating = false
            return ""
        }
    }
}

// MARK: - Commentary/Devotional Split Parser

/// Represents the parsed sections of generated Bible commentary
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
    
    /// Parse generated text into commentary and devotional sections
    /// - Parameter text: The raw generated text containing special tokens
    /// - Returns: ParsedBibleContent with separated commentary and devotional sections
    func parseGeneratedContent(_ text: String) -> ParsedBibleContent {
        print("🔍 Parsing generated content for commentary/devotional split...")
        
        // Default values
        var commentary = ""
        var devotional = ""
        
        // Parse commentary section: [START_COMMENTARY] ... [END_COMMENTARY]
        if let startRange = text.range(of: "[START_COMMENTARY]"),
           let endRange = text.range(of: "[END_COMMENTARY]") {
            let startIndex = text.index(startRange.upperBound, offsetBy: 0)
            let endIndex = endRange.lowerBound
            if startIndex < endIndex {
                commentary = String(text[startIndex..<endIndex])
                print("✅ Found commentary section: \(commentary.prefix(100))...")
            }
        }
        
        // Parse devotional section: [START_DEVOTIONAL] ... [END_DEVOTIONAL]
        if let startRange = text.range(of: "[START_DEVOTIONAL]"),
           let endRange = text.range(of: "[END_DEVOTIONAL]") {
            let startIndex = text.index(startRange.upperBound, offsetBy: 0)
            let endIndex = endRange.lowerBound
            if startIndex < endIndex {
                devotional = String(text[startIndex..<endIndex])
                print("✅ Found devotional section: \(devotional.prefix(100))...")
            }
        }
        
        // If no sections found, treat the entire text as commentary
        if commentary.isEmpty && devotional.isEmpty {
            commentary = text
            print("⚠️ No special tokens found, treating entire text as commentary")
        }
        
        // Clean up the sections
        commentary = cleanSectionText(commentary)
        devotional = cleanSectionText(devotional)
        
        print("📝 Parsed sections - Commentary: \(commentary.count) chars, Devotional: \(devotional.count) chars")
        
        return ParsedBibleContent(commentary: commentary, devotional: devotional, rawText: text)
    }
    
    /// Clean up section text by removing extra whitespace and formatting
    /// - Parameter text: Raw section text
    /// - Returns: Cleaned section text
    private func cleanSectionText(_ text: String) -> String {
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n\n", with: "\n\n") // Remove excessive line breaks
            .replacingOccurrences(of: "  ", with: " ") // Remove double spaces
    }
    
    /// Generate commentary and devotional content, returning parsed sections
    /// - Parameters:
    ///   - verseRef: Bible verse reference (e.g., "John 3:16")
    ///   - verseText: The actual verse text
    /// - Returns: ParsedBibleContent with separate commentary and devotional sections
    @MainActor
    func generateCommentaryAndDevotional(for verseRef: String, verseText: String) async -> ParsedBibleContent {
        let rawText = await generateCommentary(for: verseRef, verseText: verseText)
        return parseGeneratedContent(rawText)
    }
}
