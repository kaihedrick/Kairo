import Foundation
import CoreML

// MARK: - Small types
public struct GenCfg { public let temp: Float; public let topP: Float; public let topK: Int; public let repPenalty: Float; public let noRepeat: Int; public init(temp: Float, topP: Float, topK: Int, repPenalty: Float, noRepeat: Int) { self.temp = temp; self.topP = topP; self.topK = topK; self.repPenalty = repPenalty; self.noRepeat = noRepeat } }
public struct KVCache { public var k: [MLMultiArray]; public var v: [MLMultiArray]; public var length: Int }

public final class BibleCommentaryGeneratorCore {
    private let model: MLModel
    private let tokenizer: GPT2BPETokenizer
    private let eos: Int32 = 50256
    private let endDevotional: Int32
    private let padId: Int32?

    // MARK: Pre-allocated buffers for performance (avoid reallocating every step)
    private let inputIdsArray = try! MLMultiArray(shape: [1, 1], dataType: .int32)
    private let posIdsArray = try! MLMultiArray(shape: [1, 1], dataType: .int32)
    private let maskArray = try! MLMultiArray(shape: [1, 1], dataType: .int32)

    // MARK: Shannon entropy helper for repetition checks
    private func shannonEntropy(of ids: [Int32]) -> Double {
        guard !ids.isEmpty else { return 0 }
        var counts: [Int32: Int] = [:]
        for id in ids { counts[id, default: 0] += 1 }
        let n = Double(ids.count)
        var h = 0.0
        for c in counts.values {
            let p = Double(c) / n
            h -= p * log2(p)
        }
        return h
    }

    public init(model: MLModel, tokenizer: GPT2BPETokenizer, endDevotional: Int32, padId: Int32?) {
        self.model = model
        self.tokenizer = tokenizer
        self.endDevotional = endDevotional
        self.padId = padId
    }

    // MARK: Helper function for attention mask creation
    private func makeOneTokenMask() throws -> MLMultiArray? {
        guard let desc = model.modelDescription.inputDescriptionsByName["attention_mask"],
              let mc = desc.multiArrayConstraint else { return nil }

        let shape = mc.shape.map { n -> NSNumber in
            let v = n.intValue
            return NSNumber(value: v <= 0 ? 1 : v) // handle -1/0 → 1
        }
        let m = try MLMultiArray(shape: shape, dataType: .int32)

        let ptr = m.dataPointer.bindMemory(to: Int32.self, capacity: m.count)
        ptr.initialize(repeating: 1, count: m.count)
        return m
    }

    // MARK: Cache allocation by introspection
    public func allocateEmptyCaches() throws -> KVCache {
        let d = model.modelDescription
        var K: [MLMultiArray] = []
        var V: [MLMultiArray] = []
        var i = 0
        while let kDesc = d.inputDescriptionsByName["k_cache_\(i)"],
              let vDesc = d.inputDescriptionsByName["v_cache_\(i)"],
              let kc = kDesc.multiArrayConstraint, let vc = vDesc.multiArrayConstraint {
            let k = try MLMultiArray(shape: kc.shape, dataType: kc.dataType)
            let v = try MLMultiArray(shape: vc.shape, dataType: vc.dataType)
            // Zero the buffers
            memset(k.dataPointer, 0, k.count * (kc.dataType == .float32 ? MemoryLayout<Float32>.size : MemoryLayout<Int32>.size))
            memset(v.dataPointer, 0, v.count * (vc.dataType == .float32 ? MemoryLayout<Float32>.size : MemoryLayout<Int32>.size))
            K.append(k); V.append(v); i += 1
        }
        return KVCache(k: K, v: V, length: 0)
    }

    // MARK: One-step forward with caches — returns logits for the NEW position (optimized)
    private func forward(lastId: Int32, caches: inout KVCache, attnMask: MLMultiArray? = nil, pos: Int32? = nil) throws -> [Float] {
        var feats: [String: MLFeatureValue] = [:]

        // input_ids: [1,1] - reuse pre-allocated buffer
        inputIdsArray[0] = NSNumber(value: lastId)
        feats["input_ids"] = .init(multiArray: inputIdsArray)

        // Optional attention_mask: reuse pre-allocated buffer when provided
        if let m = attnMask {
            feats["attention_mask"] = .init(multiArray: m)
        } else if model.modelDescription.inputDescriptionsByName["attention_mask"] != nil {
            // Default to 1 for single token (always attend to current position)
            maskArray[0] = 1
            feats["attention_mask"] = .init(multiArray: maskArray)
        }

        // Optional position_ids if present - reuse pre-allocated buffer
        if let pos = pos, model.modelDescription.inputDescriptionsByName["position_ids"] != nil {
            posIdsArray[0] = NSNumber(value: pos)
            feats["position_ids"] = .init(multiArray: posIdsArray)
        }

        // KV inputs
        for i in 0..<caches.k.count {
            feats["k_cache_\(i)"] = .init(multiArray: caches.k[i])
            feats["v_cache_\(i)"] = .init(multiArray: caches.v[i])
        }

        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: feats))

        // Read logits of the last time step using helper function
        guard let logits = out.featureValue(for: "logits")?.multiArrayValue else { return [] }
        let row = logits.lastPositionLogitsRow()

        // ✅ Vocab sanity check: log row.count → expect ~50,3xx (not 50,257)
        #if DEBUG
        print("🎯 Vocab sanity: row.count = \(row.count) (expect ~50,3xx, not 50,257)")
        #endif

        // Update caches from present_* outputs
        for i in 0..<caches.k.count {
            if let pk = out.featureValue(for: "present_k_\(i)")?.multiArrayValue,
               let pv = out.featureValue(for: "present_v_\(i)")?.multiArrayValue {
                caches.k[i] = pk; caches.v[i] = pv
            }
        }
        caches.length += 1
        return row
    }

    // MARK: Sampler (compact) with repetition checks
    private func sample(_ logits: inout [Float], cfg: GenCfg, hist: [Int32]) -> Int32 {
        // ✅ Repetition check: entropy over last 100, last 16 not identical
        #if DEBUG
        if hist.count >= 16 {
            let last16 = hist.suffix(16)
            let entropy = shannonEntropy(of: Array(hist.suffix(min(100, hist.count))))
            print("🔄 Repetition check: last16 identical=\(Set(last16).count == 1), entropy(last100)=\(String(format: "%.3f", entropy)) (want > 0.6)")
        }
        #endif
        // repetition penalty
        if cfg.repPenalty > 1 { for h in hist { let i = Int(h); if i < logits.count { logits[i] /= cfg.repPenalty } } }

        // temperature (skip for greedy sampling)
        if cfg.temp != 1 { for i in 0..<logits.count { logits[i] /= cfg.temp } }
        // softmax
        let mx = logits.max() ?? 0; var s: Float = 0
        for i in 0..<logits.count { logits[i] = exp(logits[i] - mx); s += logits[i] }
        s = max(s, 1e-9)
        for i in 0..<logits.count { logits[i] /= s }
        // top‑k
        if cfg.topK > 0 && cfg.topK < logits.count {
            let idx = (0)..<logits.count
            let sorted = idx.sorted { logits[$0] > logits[$1] }
            for i in cfg.topK..<logits.count { logits[sorted[i]] = 0 }
        }
        // top‑p
        if cfg.topP < 1 {
            let idx = (0)..<logits.count
            let sorted = idx.sorted { logits[$0] > logits[$1] }
            var cum: Float = 0; var cut = sorted.count
            for i in 0..<sorted.count { cum += logits[sorted[i]]; if cum >= cfg.topP { cut = i+1; break } }
            for i in cut..<sorted.count { logits[sorted[i]] = 0 }
        }
        // sample
        let r = Float.random(in: 0..<1); var cum: Float = 0
        for i in 0..<logits.count { cum += logits[i]; if r <= cum { return Int32(i) } }
        return 0
    }

    // MARK: Greedy sampler (faster, deterministic) - optional optimization
    private func sampleGreedy(_ logits: inout [Float], cfg: GenCfg, hist: [Int32]) -> Int32 {
        // Apply repetition penalty only (skip softmax/sampling overhead)
        if cfg.repPenalty > 1 {
            for h in hist {
                let i = Int(h)
                if i < logits.count { logits[i] /= cfg.repPenalty }
            }
        }

        // Return argmax (greedy sampling) - optimized implementation
        let next = Int32(logits.enumerated().max(by: { $0.element < $1.element })!.offset)
        return next
    }

    // MARK: Performance measurement helper
    public func measureGenerationTime(promptIds: [Int32], maxNew: Int, cfg: GenCfg, stop: Set<Int32>, useGreedy: Bool = false) throws -> (tokens: [Int32], timeMs: Double) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let tokens = try generate(promptIds: promptIds, maxNew: maxNew, cfg: cfg, stop: stop, useGreedy: useGreedy)
        let endTime = CFAbsoluteTimeGetCurrent()
        let timeMs = (endTime - startTime) * 1000.0

        #if DEBUG
        print(String(format: "⚡ Generation time: %.2f ms for \(tokens.count) tokens (%.2f ms/token)", timeMs, timeMs / Double(tokens.count)))
        #endif

        return (tokens, timeMs)
    }

    // MARK: Public generate (buffered -> "all at once" UX)
    public func generate(promptIds: [Int32], maxNew: Int, cfg: GenCfg, stop: Set<Int32>, useGreedy: Bool = false) throws -> [Int32] {
        var caches = try allocateEmptyCaches()

        // Prime on prompt (step through prompt ONLY once) and keep the last logits
        var currentLogits: [Float] = []
        for (i, t) in promptIds.enumerated() {
            let stepMask = try makeOneTokenMask() // always supply if required
            currentLogits = try forward(lastId: t, caches: &caches, attnMask: stepMask, pos: Int32(i))
        }

        // Decode tokens with O(1) step cost; buffer results
        var out: [Int32] = []
        var history: [Int32] = []
        for _ in 0..<maxNew {
            var probs = currentLogits
            let next = useGreedy ? sampleGreedy(&probs, cfg: cfg, hist: history) : sample(&probs, cfg: cfg, hist: history)

            // ✅ Stop works: halt on [END_DEVOTIONAL]
            #if DEBUG
            if stop.contains(next) || next == eos {
                print("🛑 Stop condition met: token=\(next) (END_DEVOTIONAL=\(endDevotional), EOS=\(eos))")
                break
            }
            #else
            if stop.contains(next) || next == eos { break }
            #endif

            out.append(next); history.append(next)

            // ✅ Sectioning: observe markers within 500-900 tokens
            #if DEBUG
            if out.count % 100 == 0 {
                let rawText = self.tokenizer.decode(out.map(Int.init))
                let hasEndCommentary = rawText.contains("[END_COMMENTARY]")
                let hasStartDevotional = rawText.contains("[START_DEVOTIONAL]")
                let hasEndDevotional = rawText.contains("[END_DEVOTIONAL]")
                print("📊 Sectioning check @\(out.count) tokens: END_COMMENTARY=\(hasEndCommentary), START_DEVOTIONAL=\(hasStartDevotional), END_DEVOTIONAL=\(hasEndDevotional)")
            }
            #endif

            // advance with ONLY the new token
            let stepMask = try makeOneTokenMask() // always supply if required
            currentLogits = try forward(lastId: next, caches: &caches, attnMask: stepMask)
        }
        return out
    }
}