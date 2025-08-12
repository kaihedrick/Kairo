import Foundation
import CoreML
import SwiftUI
import Accelerate

enum InferenceMode { case coreml, fallback }

/// Minimal IEEE-754 half → float converter (no dependencies)
@inline(__always) func f16to32(_ h: UInt16) -> Float {
    let s = Float((h & 0x8000) >> 15)
    let e = Int((h & 0x7C00) >> 10)
    var f = Int(h & 0x03FF)

    if e == 0 {
        // subnormal
        if f == 0 { return copysign(0, s == 0 ? 1 : -1) }
        var exp = -14
        var frac = Float(f)
        while (f & 0x400) == 0 { f <<= 1; exp -= 1 }
        f &= 0x3FF
        frac = Float(f) / 1024.0
        let val = ldexpf(frac + 1.0, Int32(exp))
        return s == 0 ? val : -val
    } else if e == 31 {
        // inf / NaN
        let val = f == 0 ? Float.infinity : Float.nan
        return s == 0 ? val : -val
    } else {
        // normalized
        let val = ldexpf(Float(f) / 1024.0 + 1.0, Int32(e - 15))
        return s == 0 ? val : -val
    }
}

extension MLMultiArray {
    /// Returns a view over logits[t, 0..vocab) as Float (converting from f16 if needed).
    /// Handles both 2D [1, vocab] and 3D [1, seq, vocab] arrays.
    func rowAsFloat(atTime t: Int, vocab: Int) -> UnsafeBufferPointer<Float> {
        let shape = self.shape.map { $0.intValue }
        let rank = shape.count
        precondition(rank == 2 || rank == 3, "logits must be 2D or 3D")
        
        let seq = (rank == 3 ? shape[1] : 1)
        let tt = max(0, min(t, seq - 1))
        let offset = (rank == 3 ? tt : 0) * vocab

        switch dataType {
        case .float32:
            let base = dataPointer.bindMemory(to: Float.self, capacity: count)
            return UnsafeBufferPointer(start: base.advanced(by: offset), count: vocab)

        case .float16:
            // Convert just this row to Float to avoid touching the whole tensor
            let src = dataPointer.bindMemory(to: UInt16.self, capacity: count)
            // Allocate a tiny scratch buffer for this row
            let scratch = UnsafeMutablePointer<Float>.allocate(capacity: vocab)
            for i in 0..<vocab {
                scratch[i] = f16to32(src[offset + i])
            }
            // We return a buffer pointer; the caller should NOT retain it beyond the sampling call.
            return UnsafeBufferPointer(start: scratch, count: vocab)

        default:
            fatalError("Unsupported MLMultiArray dtype \(dataType)")
        }
    }
}

@MainActor
final class BibleCommentaryGenerator: ObservableObject {
    static let shared = BibleCommentaryGenerator()
    private static var didInit = false

    @Published var isGenerating = false
    @Published var generatedText = ""
    @Published var error: String?
    @Published private(set) var mode: InferenceMode = .fallback

    private(set) var model: MLModel?
    private var vocab: Vocab?
    private var bpe: GPT2BPEEncoder?
    private(set) var outputName: String = "logits"

    // Sampling knobs (use mild sampling by default for better diversity)
    var temperature: Float? = 0.8  // mild temperature for controlled randomness
    var topK: Int? = 40            // limit to top 40 tokens for quality
    var topP: Float? = nil         // keep nil for simplicity

    // Model/tokenizer constants loaded from assets (best practice: single source of truth)
    private var seqLen: Int = 512
    private let vocabSize: Int = 50266
    
    // Token IDs dynamically loaded from tokenizer_config.json
    private var padId: Int32 = 50265              // [PAD] - will be loaded from assets
    private var endDevotionalId: Int32 = 50264    // [END_DEVOTIONAL] - will be loaded from assets
    private var endCommentaryId: Int32 = 50262    // [END_COMMENTARY] - will be loaded from assets
    private var startCommentaryId: Int32 = 50261  // [START_COMMENTARY] - will be loaded from assets
    private var verseId: Int32 = 50257            // [VERSE_ID] - will be loaded from assets
    private var verseRefId: Int32 = 50258         // [VERSE_REF] - will be loaded from assets  
    private var verseTextId: Int32 = 50259       // [VERSE_TEXT] - will be loaded from assets
    private var verseTagId: Int32 = 50260        // [VERSE] - will be loaded from assets

    // Use existing tokenizer for prompt formatting (encoding is placeholder-level)
    private let tokenizer = GPT2Tokenizer.shared

    private init() {
        if !Self.didInit {
            Self.didInit = true
            loadResources()
        }
    }

    private func loadResources() {
        print("🚀 Starting resource loading...")
        loadTokenizerConfig()
        loadModel()
        loadVocab()
        loadBPEIfAvailable()
        parseExportReportIfAvailable()
        resolveOutputNameIfPossible()
        startupGuards()
        performIntegrityChecks()
        mode = (model != nil && vocab != nil) ? .coreml : .fallback
        print("✅ Inference mode: \(mode)")
        print("🔍 Final state - BPE loaded: \(bpe != nil), Vocab loaded: \(vocab != nil)")
    }

    private func loadTokenizerConfig() {
        guard let configURL = BundleLoader.url(name: "tokenizer_config", ext: "json") else {
            print("⚠️ tokenizer_config.json not found - using default token IDs")
            return
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            let config = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            
            if let addedTokensDecoder = config["added_tokens_decoder"] as? [String: [String: Any]] {
                // Load special token IDs from the authoritative source
                for (idStr, tokenInfo) in addedTokensDecoder {
                    guard let id = Int32(idStr), let content = tokenInfo["content"] as? String else { continue }
                    
                    switch content {
                    case "[PAD]":
                        padId = id
                    case "[END_DEVOTIONAL]":
                        endDevotionalId = id
                    case "[END_COMMENTARY]":
                        endCommentaryId = id
                    case "[START_COMMENTARY]":
                        startCommentaryId = id
                    case "[VERSE_ID]":
                        verseId = id
                    case "[VERSE_REF]":
                        verseRefId = id
                    case "[VERSE_TEXT]":
                        verseTextId = id
                    case "[VERSE]":
                        verseTagId = id
                    default:
                        break
                    }
                }
                print("✅ Loaded special token IDs from tokenizer_config.json")
                print("   PAD: \(padId), END_DEVOTIONAL: \(endDevotionalId), START_COMMENTARY: \(startCommentaryId)")
            }
        } catch {
            print("❌ Failed to load tokenizer_config.json: \(error)")
        }
    }
    
    private func loadModel() {
        // Prefer generated class if available
        do {
            let config = MLModelConfiguration()
#if targetEnvironment(simulator)
            config.computeUnits = .cpuOnly
#else
            config.computeUnits = .cpuAndNeuralEngine
#endif
            if let mdl = try? bible_commentary_model(configuration: config) {
                self.model = mdl.model
                self.mode = .coreml
                GenerationRuntime.shared.mode = .coreml
                NotificationCenter.default.post(name: .coreMLBibleModelReady, object: nil)
                print("🟢 Core ML generator ready (generated class)")
                return
            }
        }

        if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodelc") {
            do {
                let config = MLModelConfiguration()
#if targetEnvironment(simulator)
                config.computeUnits = .cpuOnly
#else
                config.computeUnits = .cpuAndNeuralEngine
#endif
                self.model = try MLModel(contentsOf: url, configuration: config)
                self.mode = .coreml
                GenerationRuntime.shared.mode = .coreml
                NotificationCenter.default.post(name: .coreMLBibleModelReady, object: nil)
                print("🟢 Core ML generator ready (.mlmodelc)")
                return
            } catch { print("❌ Failed to load .mlmodelc: \(error)") }
        }
        if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage") {
            do {
                let compiled = try MLModel.compileModel(at: url)
                let config = MLModelConfiguration()
#if targetEnvironment(simulator)
                config.computeUnits = .cpuOnly
#else
                config.computeUnits = .cpuAndNeuralEngine
#endif
                self.model = try MLModel(contentsOf: compiled, configuration: config)
                self.mode = .coreml
                GenerationRuntime.shared.mode = .coreml
                NotificationCenter.default.post(name: .coreMLBibleModelReady, object: nil)
                print("🟢 Core ML generator ready (.mlpackage)")
                return
            } catch { print("❌ Failed to load .mlpackage: \(error)") }
        }
        if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodel") {
            do {
                let config = MLModelConfiguration()
#if targetEnvironment(simulator)
                config.computeUnits = .cpuOnly
#else
                config.computeUnits = .cpuAndNeuralEngine
#endif
                self.model = try MLModel(contentsOf: url, configuration: config)
                self.mode = .coreml
                GenerationRuntime.shared.mode = .coreml
                NotificationCenter.default.post(name: .coreMLBibleModelReady, object: nil)
                print("🟢 Core ML generator ready (.mlmodel)")
                return
            } catch { print("❌ Failed to load .mlmodel: \(error)") }
        }
        if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodelc", subdirectory: "Resources/ML") {
            do {
                let config = MLModelConfiguration()
#if targetEnvironment(simulator)
                config.computeUnits = .cpuOnly
#else
                config.computeUnits = .cpuAndNeuralEngine
#endif
                self.model = try MLModel(contentsOf: url, configuration: config)
                return
            } catch { print("❌ Failed to load ML/ .mlmodelc: \(error)") }
        }
        if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage", subdirectory: "Resources/ML") {
            do {
                let compiled = try MLModel.compileModel(at: url)
                let config = MLModelConfiguration()
#if targetEnvironment(simulator)
                config.computeUnits = .cpuOnly
#else
                config.computeUnits = .cpuAndNeuralEngine
#endif
                self.model = try MLModel(contentsOf: compiled, configuration: config)
                return
            } catch { print("❌ Failed to load ML/ .mlpackage: \(error)") }
        }
        print("❌ No Core ML model found in bundle")
    }

    private func resolveOutputNameIfPossible() {
        guard let model else { return }
        let outs = model.modelDescription.outputDescriptionsByName
        if outs["logits"] != nil {
            outputName = "logits"
            return
        }
        if let name = outs.first(where: { $0.value.multiArrayConstraint?.shape.count == 3 })?.key {
            outputName = name
            print("ℹ️ Using fallback output name: \(outputName)")
        }
    }

    private func loadVocab() {
        if let url = BundleLoader.url(name: "id_to_token", ext: "json") {
            do {
                self.vocab = try Vocab.load(from: url)
                if let v = vocab { assert(v.idToToken.count == vocabSize, "Vocab mismatch: \(v.idToToken.count)") }
                print("✅ Loaded id_to_token.json @ \(url.path)")
            } catch { print("❌ Failed loading id_to_token.json: \(error)") }
        } else {
            print("⚠️ id_to_token.json not found; decoding will be limited")
        }
    }

    private func loadBPEIfAvailable() {
        guard bpe == nil else { return }
        
        // Debug: Check if files exist
        let vocabURL = BundleLoader.url(name: "vocab", ext: "json")
        let mergesURL = BundleLoader.url(name: "merges", ext: "txt")
        print("🔍 BPE Debug - vocab.json: \(vocabURL?.path ?? "NOT FOUND")")
        print("🔍 BPE Debug - merges.txt: \(mergesURL?.path ?? "NOT FOUND")")
        
        if let vocabURL = vocabURL, let mergesURL = mergesURL {
            let specialURL = BundleLoader.url(name: "special_tokens_map", ext: "json")
            let addedURL = BundleLoader.url(name: "added_tokens", ext: "json")
            print("🔍 BPE Debug - special_tokens_map.json: \(specialURL?.path ?? "NOT FOUND")")
            print("🔍 BPE Debug - added_tokens.json: \(addedURL?.path ?? "NOT FOUND")")
            
            do {
                let enc = try GPT2BPEEncoder(vocabURL: vocabURL, mergesURL: mergesURL, specialTokensURL: specialURL, addedTokensURL: addedURL)
                self.bpe = enc
                print("✅ Found vocab.json @ \(vocabURL.path)")
                print("✅ Found merges.txt @ \(mergesURL.path)")
                print("✅ Loaded GPT-2 BPE (vocab count: \(enc.vocabCount))")
            } catch {
                print("❌ Failed to initialize BPE: \(error)")
            }
        } else {
            print("⚠️ BPE assets not found; using placeholder tokenizer (special tokens only).")
        }
    }

    private func parseExportReportIfAvailable() {
        let candidates = [BundleLoader.url(name: "export_report", ext: "json")].compactMap { $0 }
        for url in candidates {
            do {
                let data = try Data(contentsOf: url)
                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let vs = obj["vocab_size"] as? Int { assert(vs == vocabSize, "export_report vocab_size=\(vs)") }
                    if let seq = obj["seq_len"] as? Int { self.seqLen = seq }
                    if let inputs = obj["inputs"] as? [String] { assert(Set(inputs) == Set(["input_ids","attention_mask"])) }
                    if let outputs = obj["outputs"] as? [String] { assert(outputs.contains("logits")) }
                    print("🧾 export_report loaded from \(url.lastPathComponent)")
                    return
                }
            } catch {
                print("⚠️ Failed to parse export_report.json at \(url): \(error)")
            }
        }
    }

    private func startupGuards() {
        // Vocab count
        if let v = vocab { print("📚 Vocab entries: \(v.idToToken.count)") }
        else { print("⚠️ Vocab not loaded; decoding will be limited") }

        // Model IO check (log last-dim)
        if let model {
            let desc = model.modelDescription
            let outputs = desc.outputDescriptionsByName
            for (name, info) in outputs {
                if let multi = info.multiArrayConstraint, let shape = multi.shape as? [NSNumber], shape.count >= 3 {
                    print("🧪 Output \(name) shape dims: \(shape.map { $0.intValue })")
                    if let last = shape.last?.intValue { print("🧪 Output last dim: \(last)") }
                }
            }
        } else {
            print("⚠️ Model not loaded")
        }

        // Special IDs sanity (log expectations)
        let expected = [50257,50258,50259,50260,50261,50262,50263,50264,50265]
        print("🔢 Expected special IDs present range: \(expected.first!)..\(expected.last!)")
    }
    
    @MainActor
    func generateCommentary(for verseRef: String, verseText: String) async -> String {
        guard !isGenerating else { return generatedText }
        isGenerating = true
        error = nil
        generatedText = ""
        
        guard let model else {
            error = "Model not loaded"
            isGenerating = false
            mode = .fallback
            return ""
        }
        guard let vocab else {
            error = "Vocab not loaded"
            isGenerating = false
            return ""
        }

        // Build prompt
        let prompt = tokenizer.formatInput(verseRef: verseRef, verseText: verseText)
        print("🧪 Generator.generate: mode=\(GenerationRuntime.shared.mode)  gen id:", ObjectIdentifier(self))
        print("🧪 Prompt preview:\n\(prompt.prefix(200))")

        // Use BPE encoder for tokenization
        let promptText = prompt
        var promptIds: [Int32]
        if let bpe {
            print("🎯 Using GPT-2 BPE encoder (vocab: \(bpe.vocabCount))")
            let ids = bpe.encode(promptText, maxLength: seqLen)
            promptIds = ids.map { Int32($0) }
            print("📝 BPE encoded first 10 ids: \(ids.prefix(10))")
            
            // Runtime sanity check: encode→decode round-trip
            if let vocab = self.vocab {
                let decoded = vocab.decode(ids: promptIds)
                let isRoundTripValid = decoded.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == promptText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !isRoundTripValid {
                    print("❌ Round-trip test FAILED:")
                    print("   Original: '\(promptText.prefix(100))'")
                    print("   Decoded:  '\(decoded.prefix(100))'")
                    assertionFailure("Tokenizer/decoder mismatch – check BPE assets")
                } else {
                    print("✅ Round-trip test PASSED")
                }
            }
        } else {
            // Require BPE encoder - no fallback to placeholder tokenizer in production
            preconditionFailure("❌ BPE assets missing; refusing to run placeholder tokenizer. Ensure vocab.json, merges.txt, and special token files are bundled.")
        }
        if promptIds.isEmpty { promptIds = [padId] }

        var mask = [Int32](repeating: 1, count: promptIds.count)
        for i in 0..<promptIds.count { if promptIds[i] == padId { mask[i] = 0 } }

        do {
            // Implement proper autoregressive generation
            let L = seqLen
            let endId = endDevotionalId  // 50264
            let prefixLen = min(promptIds.count, L)
            let maxNew = L - prefixLen  // Use remaining sequence length instead of fixed 128
            
            // Prepare full-length arrays
            var ids = [Int32](repeating: padId, count: L)
            var attnMask = [Int32](repeating: 0, count: L)
            
            // Copy prompt into the beginning
            for i in 0..<prefixLen {
                ids[i] = promptIds[i]
                attnMask[i] = mask[i]
            }
            var currentLen = prefixLen
            var generated = 0
            var didLogShapes = false
            
            print("🚀 Starting autoregressive generation from position \(currentLen)")
            
            while currentLen < L && generated < maxNew {
                // 1) Create input arrays for this step
                let inputIds = try makeInt32Array([1, L])
                let attnMaskArray = try makeInt32Array([1, L])
                
                // Fill arrays with current state
                for i in 0..<L {
                    inputIds[[0, i] as [NSNumber]] = NSNumber(value: ids[i])
                    attnMaskArray[[0, i] as [NSNumber]] = NSNumber(value: attnMask[i])
                }
                
                // 2) Run model prediction
                let provider = try MLDictionaryFeatureProvider(dictionary: [
                    "input_ids": MLFeatureValue(multiArray: inputIds),
                    "attention_mask": MLFeatureValue(multiArray: attnMaskArray)
                ])
                let out = try await model.prediction(from: provider)
                
                // 3) Extract logits with fallback - accept both 2D and 3D arrays
                var logits: MLMultiArray?
                if let l = out.featureValue(for: outputName)?.multiArrayValue { logits = l }
                if logits == nil {
                    if let l0 = out.featureValue(for: "linear_0")?.multiArrayValue { logits = l0 }
                }
                if logits == nil {
                    for name in out.featureNames {
                        if let m = out.featureValue(for: name)?.multiArrayValue, m.shape.count >= 2 { 
                            logits = m; break 
                        }
                    }
                }
                guard let logitsArray = logits else { 
                    print("❌ No logits found in model output")
                    break 
                }
                
                // 4) Sample from the last step logits - handle both 2D and 3D shapes
                let shape = logitsArray.shape.map { $0.intValue }
                let rank = shape.count
                let (Lout, vocab): (Int, Int)
                if rank == 3 {
                    Lout = shape[1]   // sequence length
                    vocab = shape[2]
                } else if rank == 2 {
                    Lout = 1          // last-step only
                    vocab = shape[1]
                } else {
                    fatalError("Unexpected logits rank: \(rank), shape: \(shape)")
                }
                
                // Clamp t to the produced length, not the input length
                let t = max(0, min(currentLen - 1, Lout - 1))
                
                // Get safe Float row
                let row: UnsafeBufferPointer<Float> = logitsArray.rowAsFloat(atTime: t, vocab: vocab)
                let nextId = sampleNextToken(from: row, vocab: vocab)
                
                // 5) Append token and advance
                if currentLen < L {
                    ids[currentLen] = nextId
                    attnMask[currentLen] = 1
                    currentLen += 1
                    generated += 1
                }
                
                // 6) Debug logging on first step
                if !didLogShapes {
                    print("📐 input_ids: [1, \(L)]  attention_mask: [1, \(L)]")
                    print("🧪 logits shape: \(shape) (rank=\(rank))")
                    if rank == 3 {
                        print("📤 logits: [1, \(Lout), \(vocab)] - 3D sequence mode")
                    } else {
                        print("📤 logits: [1, \(vocab)] - 2D last-step mode")
                    }
                    print("🔝 step \(t) sampled id: \(nextId)")
                    if let v = self.vocab {
                        let decoded = v.decode(ids: [nextId])
                        print("📝 decoded peek: '\(decoded)'")
                    }
                    didLogShapes = true
                }
                
                // 7) Stop conditions
                if nextId == endDevotionalId {
                    print("🛑 Stopped at END_DEVOTIONAL token")
                    break
                } else if nextId == endCommentaryId {
                    print("🛑 Stopped at END_COMMENTARY token")
                    break
                }
                
                // Progress update
                if generated % 10 == 0 {
                    print("⏳ Generated \(generated)/\(maxNew) tokens, currentLen=\(currentLen)")
                }
            }
            
            // 8) Decode final result
            let finalIds = Array(ids.prefix(currentLen))
            let text = vocab.decode(ids: finalIds)
            generatedText = text
            isGenerating = false
            print("✅ Generation complete: \(generated) new tokens, total length \(currentLen)")
            return text
        } catch {
            self.error = "Generation failed: \(error.localizedDescription)"
            isGenerating = false
            mode = .fallback
            return ""
        }
    }
    
    private func makeInt32Array(_ shape: [Int], fill: Int32 = 0) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .int32)
        let total = shape.reduce(1, *)
        let base = UnsafeMutablePointer<Int32>(OpaquePointer(arr.dataPointer))
        base.initialize(repeating: fill, count: total)
        return arr
    }

    private func sampleNextToken(from row: UnsafeBufferPointer<Float>, vocab: Int) -> Int32 {
        // Mask PAD token by setting its logit to -inf
        var maskedLogits = Array(UnsafeBufferPointer(start: row.baseAddress, count: vocab))
        if Int(padId) < vocab {
            maskedLogits[Int(padId)] = -Float.infinity
        }
        
        // Greedy if no sampling knobs
        if temperature == nil && topK == nil && topP == nil {
            var bestIdx = 0
            var bestVal = -Float.infinity
            for i in 0..<vocab { 
                let v = maskedLogits[i]; 
                if v > bestVal { bestVal = v; bestIdx = i } 
            }
            return Int32(bestIdx)
        }
        // Temperature + optional top-k / top-p
        let temp = max(1e-6, Double(temperature ?? 1.0))
        var indices = Array(0..<vocab)
        var scores = indices.map { Double(maskedLogits[$0]) / temp }
        // Top-k
        if let k = topK, k > 0, k < vocab {
            let threshold = scores.sorted(by: >)[min(k-1, scores.count-1)]
            var filteredIdx: [Int] = []
            var filteredScores: [Double] = []
            for (i, s) in scores.enumerated() where s >= threshold { filteredIdx.append(i); filteredScores.append(s) }
            indices = filteredIdx; scores = filteredScores
        }
        // Softmax
        let maxLogit = scores.max() ?? 0
        let exps = scores.map { exp($0 - maxLogit) }
        var sumExp = exps.reduce(0, +)
        if sumExp == 0 { sumExp = 1 }
        var probs = exps.map { $0 / sumExp }
        // Top-p (nucleus)
        if let p = topP, p > 0, p < 1 {
            let zipped = zip(indices, probs).sorted { $0.1 > $1.1 }
            var cum: Double = 0
            var kept: [(Int, Double)] = []
            for (idx, pr) in zipped { cum += pr; kept.append((idx, pr)); if cum >= Double(p) { break } }
            indices = kept.map { $0.0 }
            probs = kept.map { $0.1 }
            let sumP = probs.reduce(0, +)
            if sumP > 0 { probs = probs.map { $0 / sumP } }
        }
        // Sample
        let r = Double.random(in: 0..<1)
        var acc: Double = 0
        for (i, pr) in probs.enumerated() {
            acc += pr
            if r <= acc { return Int32(indices[i]) }
        }
        return Int32(indices.last ?? 0)
    }

    private func step(model: MLModel,
                       ids: inout [Int32],
                       mask: inout [Int32],
                       seqLen: Int) throws -> Int32? {
        let L = seqLen
        let currentLen = min(ids.count, L)

        let inputIds = try makeInt32Array([1, L])
        let attnMask = try makeInt32Array([1, L])
        for i in 0..<currentLen {
            inputIds[[0, i] as [NSNumber]] = NSNumber(value: ids[i])
            attnMask[[0, i] as [NSNumber]] = NSNumber(value: mask[i])
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "attention_mask": MLFeatureValue(multiArray: attnMask)
        ])
        let out = try model.prediction(from: provider)

        var logits: MLMultiArray?
        if let l = out.featureValue(for: outputName)?.multiArrayValue { logits = l }
        if logits == nil {
            if let l0 = out.featureValue(for: "linear_0")?.multiArrayValue { logits = l0 }
        }
        if logits == nil {
            for name in out.featureNames {
                if let m = out.featureValue(for: name)?.multiArrayValue, m.shape.count >= 3 { logits = m; break }
            }
        }
        guard let logitsArray = logits else { return nil }

        let Lout = logitsArray.shape[1].intValue   // sequence length produced
        let vocab = logitsArray.shape[2].intValue

        // Clamp t to the produced length, not the input length.
        let t = max(0, min(currentLen - 1, Lout - 1))

        // Get a pointer (slice) to the last-step logits as Float
        let row: UnsafeBufferPointer<Float> = logitsArray.rowAsFloat(atTime: t, vocab: vocab)
        let chosen = sampleNextToken(from: row, vocab: vocab)

        if ids.count < L { ids.append(chosen); mask.append(1) } else { return nil }
        return chosen
    }

    private func performIntegrityChecks() {
        print("🔍 Performing integrity checks...")
        
        // Check vocab size matches expected
        if let vocab = vocab {
            let actualSize = vocab.idToToken.count
            assert(actualSize == vocabSize, "❌ Vocab size mismatch: expected \(vocabSize), got \(actualSize)")
            print("✅ Vocab size check passed: \(actualSize)")
        }
        
        // Check special token mappings are correct  
        if let vocab = vocab {
            let tokenChecks: [(Int32, String)] = [
                (startCommentaryId, "[START_COMMENTARY]"),
                (endCommentaryId, "[END_COMMENTARY]"),
                (endDevotionalId, "[END_DEVOTIONAL]"),
                (padId, "[PAD]"),
                (verseId, "[VERSE_ID]"),
                (verseRefId, "[VERSE_REF]"),
                (verseTextId, "[VERSE_TEXT]"),
                (verseTagId, "[VERSE]")
            ]
            
            for (id, expectedToken) in tokenChecks {
                if let actualToken = vocab.idToToken[id] {
                    assert(actualToken == expectedToken, "❌ Token mapping mismatch: ID \(id) maps to '\(actualToken)', expected '\(expectedToken)'")
                } else {
                    print("⚠️ Token ID \(id) not found in vocab for '\(expectedToken)'")
                }
            }
            print("✅ Special token mapping checks passed")
        }
        
        // Check model output shape if available
        if let model = model {
            let outputs = model.modelDescription.outputDescriptionsByName
            if let logitsInfo = outputs[outputName],
               let constraint = logitsInfo.multiArrayConstraint,
               let shape = constraint.shape as? [NSNumber] {
                let dims = shape.map { $0.intValue }
                if dims.count >= 3 && dims[2] != vocabSize {
                    print("⚠️ Model output vocab dim mismatch: \(dims[2]) != \(vocabSize)")
                } else {
                    print("✅ Model output shape check passed: \(dims)")
                }
            }
        }
        
        print("🔍 Integrity checks complete")
    }
}
