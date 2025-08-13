// filepath: BibleAppPOCV2/Services/BibleCommentaryGenerator.swift
import Foundation
import CoreML
import SwiftUI

enum InferenceMode { case coreml, fallback }

extension Notification.Name {
    static let coreMLBibleModelReady = Notification.Name("coreMLBibleModelReady")
}

@MainActor
final class BibleCommentaryGenerator: ObservableObject {
    static let shared = BibleCommentaryGenerator()
    private static var didInit = false

    @Published var isGenerating = false
    @Published var generatedText = ""
    @Published var error: String?
    @Published private(set) var mode: InferenceMode = .fallback
    @Published private(set) var isReady = false

    // Core pieces
    private(set) var model: MLModel?
    private var vocab: Vocab?
    private var bpe: GPT2BPEEncoder?
    private var tokenizerSvc: TokenizerService?

    private(set) var outputName: String = "logits"

#if targetEnvironment(simulator)
    private let TEMP: Float = 0.0
    private let TOPK: Int = 0
    private let TOPP: Float = 1.0
#else
    private let TEMP: Float = 0.9
    private let TOPK: Int = 100
    private let TOPP: Float = 0.95
#endif
    private let REP: Float = 1.15
    private let MAX_NEW: Int = 800
    private let MIN_NEW: Int = 40

    // Model IO
    private var seqLen: Int = 512
    private var kvSpec = KVSpec(nLayer: 12, nHead: 12, headDim: 64)
    private var caches: KVCaches?

    struct KVSpec: CustomStringConvertible {
        let nLayer: Int; let nHead: Int; let headDim: Int
        var description: String { "L\(nLayer) H\(nHead) D\(headDim)" }
    }
    struct KVCaches { var k: [MLMultiArray]; var v: [MLMultiArray] }

    // Special IDs
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
        print("🚀 Loading resources…")

        do { self.vocab = try Vocab.load(); print("✅ Vocab ready (\(vocab?.idToToken.count ?? 0))") }
        catch { print("❌ Vocab error:", error.localizedDescription) }

        self.bpe = GPT2BPEEncoder.shared
        print("✅ BPE ready (vocab: \(bpe?.vocabCount ?? 0))")

        if let report = BundleLoader.url(name: "export_report", ext: "json"),
           let data = try? Data(contentsOf: report),
           let obj  = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
            if let io = obj["model_io"] as? [String:Any], let L = io["seq_len"] as? Int {
                seqLen = L
            } else if let L = obj["seq_len"] as? Int { seqLen = L }
            if let io = obj["model_io"] as? [String:Any],
               let nl = io["n_layer"] as? Int, let nh = io["n_head"] as? Int, let hd = io["head_dim"] as? Int {
                kvSpec = KVSpec(nLayer: nl, nHead: nh, headDim: hd)
            }
            print("✅ export_report: seq_len=\(seqLen), kv=\(kvSpec))")
        }

        if let cfgURL = BundleLoader.url(name: "tokenizer_config", ext: "json"),
           let data = try? Data(contentsOf: cfgURL),
           let cfg = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
           let dec = cfg["added_tokens_decoder"] as? [String:[String:Any]] {
            for (k,v) in dec {
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
            print("✅ Special IDs: PAD=\(padId)")
        }

        if let bpe = self.bpe {
            tokenizerSvc = TokenizerService(
                bpe: bpe,
                ids: .init(
                    verseId: verseId, verseRefId: verseRefId, verseTextId: verseTextId, verseTagId: verseTagId,
                    startCommentaryId: startCommentaryId, endCommentaryId: endCommentaryId,
                    startDevotionalId: startDevotionalId, endDevotionalId: endDevotionalId, padId: padId
                )
            )
        }

        loadModel()
        isReady = (model != nil && vocab != nil && bpe != nil && tokenizerSvc != nil)
        mode = isReady ? .coreml : .fallback
        if isReady {
            NotificationCenter.default.post(name: .coreMLBibleModelReady, object: nil)
            print("✅ Generator ready")
        } else {
            print("⚠️ Generator not ready")
        }
    }

    private func loadModel() {
        let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
        cfg.computeUnits = .cpuOnly
#else
        cfg.computeUnits = .cpuAndNeuralEngine
#endif
        if let gen = try? bible_commentary_model(configuration: cfg) {
            model = gen.model
            outputName = "logits"
            print("🟢 Core ML (generated class) loaded")
            return
        }
        if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage") ??
                      Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: url, configuration: cfg)
            outputName = "logits"
            print("🟢 Core ML (bundle) loaded")
        }
    }

    // MARK: - KV allocator

    private func allocateZeroCaches() throws -> KVCaches {
        guard let model else { throw NSError(domain: "KV", code: -10,
            userInfo: [NSLocalizedDescriptionKey:"Model not loaded"]) }
        var k: [MLMultiArray] = []; var v: [MLMultiArray] = []
        let inputs = model.modelDescription.inputDescriptionsByName

        func alloc(_ name: String) throws -> MLMultiArray {
            if let c = inputs[name]?.multiArrayConstraint,
               let shape = c.shape as? [NSNumber] {
                let arr = try MLMultiArray(shape: shape, dataType: c.dataType)
                if arr.dataType == .float16 {
                    arr.dataPointer.bindMemory(to: UInt16.self, capacity: arr.count)
                        .initialize(repeating: 0, count: arr.count)
                } else {
                    arr.dataPointer.bindMemory(to: Float.self, capacity: arr.count)
                        .initialize(repeating: 0, count: arr.count)
                }
                return arr
            } else {
                let arr = try MLMultiArray(
                    shape: [1, NSNumber(value: kvSpec.nHead), 1, NSNumber(value: kvSpec.headDim)],
                    dataType: .float16
                )
                arr.dataPointer.bindMemory(to: UInt16.self, capacity: arr.count)
                    .initialize(repeating: 0, count: arr.count)
                return arr
            }
        }

        for i in 0..<kvSpec.nLayer {
            k.append(try alloc("k_cache_\(i)"))
            v.append(try alloc("v_cache_\(i)"))
        }
        return KVCaches(k: k, v: v)
    }

    // MARK: - Sampling

    @inline(__always) private func softmax(_ x: inout [Float]) {
        let m = x.max() ?? 0
        var s: Float = 0
        for i in 0..<x.count { x[i] = expf(x[i] - m); s += x[i] }
        if s > 0 { for i in 0..<x.count { x[i] /= s } }
    }

    private func maskStructural(_ logits: inout [Float]) {
        let n = logits.count
        for sid in [padId, startCommentaryId, endCommentaryId,
                    startDevotionalId, endDevotionalId,
                    verseId, verseRefId, verseTextId, verseTagId] {
            let i = Int(sid); if i >= 0 && i < n { logits[i] = -.infinity }
        }
    }

    private func sample(_ row: [Float], recent: ArraySlice<Int32>) -> Int32 {
        var logits = row
        maskStructural(&logits)

        let n = logits.count
        if REP > 1.0 {
            for id in recent.suffix(64) {
                let i = Int(id)
                if i >= 0 && i < n, logits[i].isFinite { logits[i] /= REP }
            }
        }
        if TEMP > 0 && TEMP != 1.0 { for i in 0..<n { logits[i] /= TEMP } }
        if TOPK > 0 && TOPK < n {
            let thr = logits.enumerated().sorted(by: { $0.element > $1.element })[TOPK-1].element
            for i in 0..<n where logits[i] < thr { logits[i] = -.infinity }
        }
        if TOPP < 1.0 {
            var probs = logits
            softmax(&probs)
            let sorted = probs.enumerated().sorted { $0.element > $1.element }
            var cum: Float = 0
            var keep = Set<Int>()
            for (i,p) in sorted { cum += p; keep.insert(i); if cum >= TOPP { break } }
            for i in 0..<n where !keep.contains(i) { logits[i] = -.infinity }
        }
        let best = (0..<n).max(by: { logits[$0] < logits[$1] }) ?? 0
        return Int32(best)
    }

    // MARK: - Generation

    @MainActor
    func generateCommentary(for verseRef: String, verseText: String) async -> String {
        guard let model, let vocab, let tokenizerSvc else {
            error = "Model/tokenizer not ready"; return ""
        }
        isGenerating = true; error = nil; generatedText = ""

        let promptIds = tokenizerSvc.encodePrompt(verseRef: verseRef, verseText: verseText, seqLen: seqLen)
        if promptIds.isEmpty { isGenerating = false; return "" }

        // Fresh caches per request (critical!)
        do { caches = try allocateZeroCaches() }
        catch {
            self.error = "Cache allocation failed: \(error.localizedDescription)"
            self.isGenerating = false
            return ""
        }

        // Warm pass
        do {
            let inputIds = try makeInt32Array([1, promptIds.count])
            let mask     = try makeInt32Array([1, promptIds.count])
            let ibase = UnsafeMutablePointer<Int32>(OpaquePointer(inputIds.dataPointer))
            let mbase = UnsafeMutablePointer<Int32>(OpaquePointer(mask.dataPointer))
            for i in 0..<promptIds.count { ibase[i] = promptIds[i]; mbase[i] = 1 }

            var dict: [String:MLFeatureValue] = [
                "input_ids": MLFeatureValue(multiArray: inputIds),
                "attention_mask": MLFeatureValue(multiArray: mask)
            ]
            for i in 0..<kvSpec.nLayer {
                dict["k_cache_\(i)"] = MLFeatureValue(multiArray: caches!.k[i])
                dict["v_cache_\(i)"] = MLFeatureValue(multiArray: caches!.v[i])
            }
            let out = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: dict))

            var kNext:[MLMultiArray]=[]; var vNext:[MLMultiArray]=[]
            for i in 0..<kvSpec.nLayer {
                guard let k = out.featureValue(for: "present_k_\(i)")?.multiArrayValue,
                      let v = out.featureValue(for: "present_v_\(i)")?.multiArrayValue else {
                    throw NSError(domain: "KV", code: -1)
                }
                kNext.append(k); vNext.append(v)
            }
            caches = KVCaches(k: kNext, v: vNext)
        } catch {
            self.error = "Warm pass failed: \(error.localizedDescription)"
            self.isGenerating = false
            return ""
        }

        // Decode loop
        var ids = promptIds
        var produced = 0
        var done = false

        while produced < MAX_NEW && !done {
            do {
                let inp = try makeInt32Array([1,1], fill: ids.last ?? padId)
                let msk = try makeInt32Array([1,1], fill: 1)

                var dict:[String:MLFeatureValue] = [
                    "input_ids": MLFeatureValue(multiArray: inp),
                    "attention_mask": MLFeatureValue(multiArray: msk)
                ]
                for i in 0..<kvSpec.nLayer {
                    dict["k_cache_\(i)"] = MLFeatureValue(multiArray: caches!.k[i])
                    dict["v_cache_\(i)"] = MLFeatureValue(multiArray: caches!.v[i])
                }

                let out = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: dict))

                var kNext:[MLMultiArray]=[]; var vNext:[MLMultiArray]=[]
                for i in 0..<kvSpec.nLayer {
                    guard let k = out.featureValue(for: "present_k_\(i)")?.multiArrayValue,
                          let v = out.featureValue(for: "present_v_\(i)")?.multiArrayValue else {
                        throw NSError(domain: "KV", code: -2)
                    }
                    kNext.append(k); vNext.append(v)
                }
                caches = KVCaches(k: kNext, v: vNext)

                guard let logits = out.featureValue(for: outputName)?.multiArrayValue else {
                    throw NSError(domain: "KV", code: -3,
                                  userInfo: [NSLocalizedDescriptionKey:"No logits in output"])
                }
                let row = logits.lastVocabRow()
                let next = sample(row, recent: ids.suffix(64))

                ids.append(next); produced += 1

                // prevent too-early stop
                if next == endDevotionalId && produced < MIN_NEW { continue }
                if next == endDevotionalId { done = true }

                if produced % 8 == 0 || done {
                    self.generatedText = vocab.decode(ids: ids)
                }
            } catch {
                self.error = "Step failed: \(error.localizedDescription)"
                break
            }
        }

        let final = vocab.decode(ids: ids)
        self.generatedText = final
        self.isGenerating = false
        return final
    }

    /// Generate commentary and devotional content, returning parsed sections
    @MainActor
    func generateCommentaryAndDevotional(for verseRef: String, verseText: String) async -> ParsedBibleContent {
        let rawText = await generateCommentary(for: verseRef, verseText: verseText)
        return parseGeneratedContent(rawText)
    }

    /// Parse generated text into commentary and devotional sections
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
        return ParsedBibleContent(commentary: clean(commentary),
                                  devotional: clean(devotional),
                                  rawText: text)
    }

    // Helpers
    private func makeInt32Array(_ shape:[Int], fill:Int32 = 0) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .int32)
        let total = shape.reduce(1, *)
        let base = UnsafeMutablePointer<Int32>(OpaquePointer(arr.dataPointer))
        base.initialize(repeating: fill, count: total)
        return arr
    }
}

// MARK: - Commentary/Devotional Split Types

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
