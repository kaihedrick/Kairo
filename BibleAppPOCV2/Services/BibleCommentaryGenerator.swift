// filepath: BibleAppPOCV2/Services/BibleCommentaryGenerator.swift
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
    @Published private(set) var isReady = false

    private(set) var model: MLModel?
    private var vocab: Vocab?
    private var bpe: GPT2BPEEncoder?
    private(set) var outputName: String = "logits"
    
    private var loadTask: Task<Void, Error>?

    // Sampling knobs (use mild sampling by default for better diversity)
    var temperature: Float? = 0.8  // mild temperature for controlled randomness
    var topK: Int? = 100           // limit to top 100 tokens for quality (increased from 40)
    var topP: Float? = 0.92        // nucleus sampling for better diversity (increased from 0.9)
    var repetitionPenalty: Float = 1.15  // penalize repeated tokens (increased from 1.1)

    // Model/tokenizer constants loaded from assets (best practice: single source of truth)
    private var seqLen: Int = 512      // Default, will be loaded from export_report.json
    private let vocabSize: Int = 50266
    
    // Token IDs dynamically loaded from tokenizer_config.json
    private var padId: Int32 = 50265              // [PAD] - will be loaded from assets
    private var endDevotionalId: Int32 = 50264    // [END_DEVOTIONAL] - will be loaded from assets
    private var endCommentaryId: Int32 = 50262    // [END_COMMENTARY] - will be loaded from assets
    private var startCommentaryId: Int32 = 50261  // [START_COMMENTARY] - will be loaded from assets
    private var startDevotionalId: Int32 = 50263  // [START_DEVOTIONAL] - will be loaded from assets
    private var verseId: Int32 = 50257            // [VERSE_ID] - will be loaded from assets
    private var verseRefId: Int32 = 50258         // [VERSE_REF] - will be loaded from assets  
    private var verseTextId: Int32 = 50259       // [VERSE_TEXT] - will be loaded from assets
    private var verseTagId: Int32 = 50260        // [VERSE] - will be loaded from assets

    // Use BPE tokenizer for prompt formatting
    private let tokenizer = GPT2BPEEncoder.shared

    private init() {
        if !Self.didInit {
            Self.didInit = true
            loadResources()
        }
    }

    private func loadResources() {
        print("🚀 Starting resource loading...")
        
        // Load all required assets
        loadTokenizerConfig()
        loadVocab()
        loadBPEIfAvailable()
        parseExportReportIfAvailable()
        
        // Load Core ML model
        loadModel()
        
        // Validate everything on startup
        performStartupValidation()
        
        // Set final state
        if isReady {
            mode = .coreml
            GenerationRuntime.shared.mode = .coreml
            NotificationCenter.default.post(name: .coreMLBibleModelReady, object: nil)
            print("✅ CoreML mode activated and notification sent")
        } else {
            mode = .fallback
            GenerationRuntime.shared.mode = .fallback
            print("⚠️ Fallback mode activated due to validation failures")
        }
        
        print("🔍 Final state - BPE loaded: \(bpe != nil), Vocab loaded: \(vocab != nil), Model loaded: \(model != nil)")
    }
    
    func ready() async throws {
        if isReady { return }
        if let t = loadTask { return try await t.value }
        
        loadTask = Task {
            // Wait for resources to be loaded
            while !isReady && mode == .fallback {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            // Run a quick self-test
            guard let testModel = model, let testVocab = vocab else {
                throw NSError(domain: "BibleCommentaryGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model or vocab not loaded"])
            }
            
            // Test tokenization round-trip
            let testText = "Test"
            if let bpe = bpe {
                let encoded = bpe.encode(testText, maxLength: 10)
                let encodedInt32 = encoded.map { Int32($0) }
                let decoded = testVocab.decode(ids: encodedInt32)
                guard decoded == testText else {
                    throw NSError(domain: "BibleCommentaryGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tokenizer round-trip failed"])
                }
            }
            
            self.isReady = true
            print("✅ Generator ready and self-tested")
        }
        
        do { 
            try await loadTask!.value 
        } catch {
            loadTask = nil
            throw error
        }
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
                    case "[START_DEVOTIONAL]":
                        startDevotionalId = id
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
                print("🟢 Core ML generator ready (generated class)")
                return
            }
        }

        // Try loading from bundle resources
        let modelExtensions = ["mlmodelc", "mlpackage", "mlmodel"]
        for ext in modelExtensions {
            if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: ext) {
                do {
                    let config = MLModelConfiguration()
#if targetEnvironment(simulator)
                    config.computeUnits = .cpuOnly
#else
                    config.computeUnits = .cpuAndNeuralEngine
#endif
                    
                    if ext == "mlpackage" {
                        let compiled = try MLModel.compileModel(at: url)
                        self.model = try MLModel(contentsOf: compiled, configuration: config)
                    } else {
                        self.model = try MLModel(contentsOf: url, configuration: config)
                    }
                    
                    print("🟢 Core ML generator ready (\(ext))")
                    return
                } catch { 
                    print("❌ Failed to load \(ext): \(error)") 
                }
            }
        }
        
        // Try loading from Resources/ML subdirectory
        for ext in modelExtensions {
            if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: ext, subdirectory: "Resources/ML") {
                do {
                    let config = MLModelConfiguration()
#if targetEnvironment(simulator)
                    config.computeUnits = .cpuOnly
#else
                    config.computeUnits = .cpuAndNeuralEngine
#endif
                    
                    if ext == "mlpackage" {
                        let compiled = try MLModel.compileModel(at: url)
                        self.model = try MLModel(contentsOf: compiled, configuration: config)
                    } else {
                        self.model = try MLModel(contentsOf: url, configuration: config)
                    }
                    
                    print("🟢 Core ML generator ready (Resources/ML/\(ext))")
                    return
                } catch { 
                    print("❌ Failed to load Resources/ML/\(ext): \(error)") 
                }
            }
        }
        
        print("❌ No Core ML model found in bundle")
        // Don't set isReady = false here, let the validation process handle it
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
                if let v = vocab { 
                    assert(v.idToToken.count == vocabSize, "Vocab mismatch: \(v.idToToken.count)")
                    print("✅ Loaded id_to_token.json @ \(url.path)")
                }
            } catch { 
                print("❌ Failed loading id_to_token.json: \(error)") 
            }
        } else {
            print("⚠️ id_to_token.json not found; decoding will be limited")
        }
    }

    private func loadBPEIfAvailable() {
        guard bpe == nil else { return }
        
        // Debug: Check if files exist
        let vocabURL = BundleLoader.url(name: "vocab", ext: "json")
        let mergesURL = BundleLoader.url(name: "merges", ext: "txt")
        let idToTokenURL = BundleLoader.url(name: "id_to_token", ext: "json")
        let specialURL = BundleLoader.url(name: "special_tokens_map", ext: "json")
        let addedURL = BundleLoader.url(name: "added_tokens", ext: "json")
        
        print("🔍 BPE Asset Check:")
        print("   vocab.json: \(vocabURL?.path ?? "❌ NOT FOUND")")
        print("   merges.txt: \(mergesURL?.path ?? "❌ NOT FOUND")")
        print("   id_to_token.json: \(idToTokenURL?.path ?? "❌ NOT FOUND")")
        print("   special_tokens_map.json: \(specialURL?.path ?? "❌ NOT FOUND")")
        print("   added_tokens.json: \(addedURL?.path ?? "❌ NOT FOUND")")
        
        // Use the singleton BPE tokenizer
        self.bpe = GPT2BPEEncoder.shared
        print("✅ BPE tokenizer loaded (vocab count: \(bpe!.vocabCount))")
    }

    private func parseExportReportIfAvailable() {
        let candidates = [BundleLoader.url(name: "export_report", ext: "json")].compactMap { $0 }
        for url in candidates {
            do {
                let data = try Data(contentsOf: url)
                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Validate vocab_size
                    if let vs = obj["vocab_size"] as? Int { 
                        assert(vs == vocabSize, "export_report vocab_size=\(vs)")
                        print("✅ Vocab size validated: \(vs)")
                    }
                    
                    // Extract seq_len from nested model_io structure
                    if let modelIO = obj["model_io"] as? [String: Any],
                       let seq = modelIO["seq_len"] as? Int {
                        self.seqLen = seq
                        print("✅ Updated seq_len from export_report: \(seq)")
                    }
                    
                    // Legacy flat structure support
                    if let seq = obj["seq_len"] as? Int { 
                        self.seqLen = seq 
                        print("✅ Updated seq_len (legacy): \(seq)")
                    }
                    
                    print("🧾 export_report loaded from \(url.lastPathComponent)")
                    return
                }
            } catch {
                print("⚠️ Failed to parse export_report.json at \(url): \(error)")
            }
        }
    }

    private func performStartupValidation() {
        print("🔍 Performing startup validation...")
        
        // 1. Validate vocab_size == 50266
        if let vocab = vocab {
            let actualSize = vocab.idToToken.count
            if actualSize != vocabSize {
                print("❌ Vocab size validation failed: expected \(vocabSize), got \(actualSize)")
                isReady = false
                return
            }
            print("✅ Vocab size validation passed: \(actualSize)")
        } else {
            print("❌ Vocab not loaded")
            isReady = false
            return
        }
        
        // 2. Validate seq_len == 512
        if seqLen != 512 {
            print("❌ Sequence length validation failed: expected 512, got \(seqLen)")
            isReady = false
            return
        }
        print("✅ Sequence length validation passed: \(seqLen)")
        
        // 3. Validate special IDs are present
        let specialTokenChecks: [(Int32, String)] = [
            (startCommentaryId, "[START_COMMENTARY]"),
            (endCommentaryId, "[END_COMMENTARY]"),
            (endDevotionalId, "[END_DEVOTIONAL]"),
            (padId, "[PAD]"),
            (startDevotionalId, "[START_DEVOTIONAL]"),
            (verseId, "[VERSE_ID]"),
            (verseRefId, "[VERSE_REF]"),
            (verseTextId, "[VERSE_TEXT]"),
            (verseTagId, "[VERSE]")
        ]
        
        for (id, expectedToken) in specialTokenChecks {
            if let actualToken = vocab?.idToToken[id] {
                if actualToken != expectedToken {
                    print("❌ Special token validation failed: ID \(id) maps to '\(actualToken)', expected '\(expectedToken)'")
                    isReady = false
                    return
                }
            } else {
                print("❌ Special token validation failed: ID \(id) not found in vocab for '\(expectedToken)'")
                isReady = false
                return
            }
        }
        print("✅ Special token validation passed")
        
        // 4. Validate BPE round-trip encode→decode succeeds
        if let bpe = bpe, let vocab = vocab {
            let testText = "Test round-trip validation"
            let encoded = bpe.encode(testText, maxLength: 20)
            let encodedInt32 = encoded.map { Int32($0) }
            let decoded = vocab.decode(ids: encodedInt32)
            
            if decoded.trimmingCharacters(in: .whitespacesAndNewlines) != testText.trimmingCharacters(in: .whitespacesAndNewlines) {
                print("❌ BPE round-trip validation failed:")
                print("   Original: '\(testText)'")
                print("   Decoded:  '\(decoded)'")
                isReady = false
                return
            }
            print("✅ BPE round-trip validation passed")
        } else {
            print("❌ BPE tokenizer not available for round-trip validation")
            isReady = false
            return
        }
        
        // 5. Validate Core ML model is loaded
        if model == nil {
            print("❌ Core ML model not loaded")
            isReady = false
            return
        }
        print("✅ Core ML model validation passed")
        
        // 6. Resolve output name
        resolveOutputNameIfPossible()
        
        // All validations passed
        isReady = true
        print("✅ All startup validations passed - generator is ready")
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
            GenerationRuntime.shared.mode = .fallback
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

        do {
            // Allocate reusable buffers for single-step I/O
            let inputIdsBuffer = try makeInt32Array([1, seqLen])
            let attentionMaskBuffer = try makeInt32Array([1, seqLen])
            
            // Prepare generation state
            let L = seqLen
            let endId = endDevotionalId  // 50264
            let prefixLen = min(promptIds.count, L)
            let maxNew = 400  // Allow enough tokens to reach both commentary and devotional sections
            
            // Initialize full-length arrays
            var ids = [Int32](repeating: padId, count: L)
            var attnMask = [Int32](repeating: 0, count: L)  // Start with all 0s
            
            // Copy prompt into the beginning
            for i in 0..<prefixLen {
                ids[i] = promptIds[i]
                attnMask[i] = 1  // 1 for real tokens
            }
            
            // Set mask: 1 for real tokens, 0 for padding (right side)
            for i in prefixLen..<L {
                attnMask[i] = 0  // 0 for padding
            }
            
            print("🔧 Initial setup: prefixLen=\(prefixLen), seqLen=\(L)")
            print("🔧 Initial mask: \(Array(attnMask.prefix(prefixLen))) (length: \(prefixLen))")
            
            var currentLen = prefixLen
            var generated = 0
            var didLogShapes = false
            
            print("🚀 Starting autoregressive generation from position \(currentLen)")
            
            while currentLen < L && generated < maxNew {
                // 1) Reuse buffers - fill with current state
                fillInputBuffer(inputIdsBuffer, with: ids, currentLen: currentLen, seqLen: L)
                fillMaskBuffer(attentionMaskBuffer, with: attnMask, currentLen: currentLen, seqLen: L)
                
                // 2) Call model with reusable buffers
                let provider = try MLDictionaryFeatureProvider(dictionary: [
                    "input_ids": MLFeatureValue(multiArray: inputIdsBuffer),
                    "attention_mask": MLFeatureValue(multiArray: attentionMaskBuffer)
                ])
                let out = try await model.prediction(from: provider)
                
                // 3) Read logits (shape [1, 50266], last-step)
                guard let logitsArray = out.featureValue(for: outputName)?.multiArrayValue else {
                    print("❌ No logits found in model output")
                    break
                }
                
                // Validate logits shape
                let shape = logitsArray.shape.map { $0.intValue }
                let expectedShape = [1, vocabSize]
                guard shape == expectedShape else {
                    print("❌ Unexpected logits shape: \(shape), expected: \(expectedShape)")
                    break
                }
                
                // 4) Sample next token (greedy/top-k/top-p)
                // Safely create logits buffer using MLShapedArray for contiguity & dtype safety
                let actualVocabSize = shape[1]  // Use actual shape from logits array
                
                // Preferred: MLShapedArray route (handles contiguity & dtype)
                let logitsBuffer: UnsafeBufferPointer<Float>
                do {
                    let shaped = try MLShapedArray<Float32>(logitsArray)
                    let scalars = shaped.scalars
                    logitsBuffer = scalars.withUnsafeBufferPointer { $0 }
                } catch {
                    print("❌ Failed to create MLShapedArray: \(error)")
                    // Fallback to direct buffer access (less safe but functional)
                    let count = logitsArray.count
                    let ptr = logitsArray.dataPointer.bindMemory(to: Float.self, capacity: count)
                    logitsBuffer = UnsafeBufferPointer(start: ptr, count: count)
                }
                
                // One-time sanity logs right before the first sampling step
                if generated == 0 {
                    print("🔎 logits row.count = \(logitsBuffer.count), MLMultiArray.count = \(logitsArray.count), padId = \(padId)")
                    print("🔎 Expected: row.count == 50266. If it ever differs, you'll see it in logs without crashing.")
                }
                
                let nextId = sampleNextToken(from: logitsBuffer, step: generated, recentTokens: Array(ids.prefix(currentLen)))
                
                // 5) Append to ids and update mask
                if currentLen < L {
                    ids[currentLen] = nextId
                    attnMask[currentLen] = 1  // 1 for real tokens
                    currentLen += 1
                    generated += 1
                    
                    // Ensure right side is zeroed (attention mask should be 0 for padded positions)
                    for i in currentLen..<L {
                        attnMask[i] = 0
                    }
                    
                    print("🔧 Step \(generated): currentLen=\(currentLen), token=\(nextId)")
                }
                
                // 6) Debug logging on first step
                if !didLogShapes {
                    print("📐 input_ids: [1, \(L)]  attention_mask: [1, \(L)]")
                    print("🧪 logits shape: \(shape) (rank=\(shape.count))")
                    print("🔝 step 0 sampled id: \(nextId)")
                    if let v = self.vocab {
                        let decoded = v.decode(ids: [nextId])
                        print("📝 decoded peek: '\(decoded)'")
                    }
                    didLogShapes = true
                }
                
                // 7) Step-by-step instrumentation (first 20 steps)
                if generated < 20 {
                    let top5 = topKIndices(from: logitsBuffer, k: 5, vocab: self.vocab)
                    print("🔍 t=\(currentLen-1) currLen=\(currentLen) top5=\(top5)")
                    print("🔍 next=\(nextId) '\(self.vocab?.idToToken[nextId] ?? "?")'")
                    
                    // Show last 10 tokens for context
                    let lastTokens = Array(ids.prefix(currentLen).suffix(10))
                    let lastDecoded = self.vocab?.decode(ids: lastTokens) ?? "?"
                    print("🔍 last 10: '\(lastDecoded)'")
                }
                
                // 8) Stop when [END_DEVOTIONAL] or length limit hit
                if nextId == endId {
                    print("🏁 Generated end token, stopping generation")
                    break
                }
                
                // 9) Update UI with partial results
                let partialIds = Array(ids.prefix(currentLen))
                let partialText = self.vocab?.decode(ids: partialIds) ?? ""
                await MainActor.run {
                    self.generatedText = partialText
                }
            }
            
            // Final decode and return
            let finalIds = Array(ids.prefix(currentLen))
            let finalText = vocab.decode(ids: finalIds)
            print("✅ Generation complete: \(generated) new tokens")
            
            await MainActor.run {
                self.generatedText = finalText
                self.isGenerating = false
            }
            
            return finalText
            
        } catch {
            await MainActor.run {
                self.error = "Generation failed: \(error.localizedDescription)"
                self.isGenerating = false
            }
            print("❌ Generation error: \(error)")
            return ""
        }
    }
    
    /// Fill reusable buffer with current state
    private func fillInputBuffer(_ buffer: MLMultiArray, with values: [Int32], currentLen: Int, seqLen: Int) {
        let base = UnsafeMutablePointer<Int32>(OpaquePointer(buffer.dataPointer))
        
        // Copy current values
        for i in 0..<currentLen {
            base[i] = values[i]
        }
        
        // Fill remaining with padding
        for i in currentLen..<seqLen {
            base[i] = padId
        }
    }
    
    /// Fill attention mask buffer with current state
    private func fillMaskBuffer(_ buffer: MLMultiArray, with mask: [Int32], currentLen: Int, seqLen: Int) {
        let base = UnsafeMutablePointer<Int32>(OpaquePointer(buffer.dataPointer))
        
        // Copy current mask values
        for i in 0..<currentLen {
            base[i] = mask[i]
        }
        
        // Fill remaining with 0 (padding)
        for i in currentLen..<seqLen {
            base[i] = 0
        }
    }

    private func makeInt32Array(_ shape: [Int], fill: Int32 = 0) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .int32)
        let total = shape.reduce(1, *)
        let base = UnsafeMutablePointer<Int32>(OpaquePointer(arr.dataPointer))
        base.initialize(repeating: fill, count: total)
        return arr
    }

    private func shouldBanPunctuation(_ tokens: [Int32]) -> Bool {
        // Ban punctuation if last 2 tokens are punctuation
        let last2 = tokens.suffix(2)
        return last2.count == 2 && last2.allSatisfy { isPunctToken($0) }
    }
    
    private func isPunctToken(_ id: Int32) -> Bool {
        // Common punctuation tokens: , . : ; ) " ( 
        let punctIds: Set<Int32> = [11, 13, 25, 26, 8, 357]
        return punctIds.contains(id)
    }
    
    private func isLetterToken(_ id: Int32) -> Bool {
        // Check if token represents a letter (this is a simplified check)
        // In practice, you'd want to decode and check the actual content
        return id > 1000 && id < 50000  // Most letter tokens are in this range
    }
    
    private func applyMasksAndPenalties(_ logits: inout [Float],
                                       ids: [Int32],
                                       step: Int,
                                       padId: Int,
                                       earlyWS: Bool,
                                       banPunctNow: Bool,
                                       noRepeatN: Int = 3,
                                       repPenalty: Float = 1.15,
                                       bannedSpecials: Set<Int>) {
        
        // 0) never sample PAD & banned specials
        for id in bannedSpecials.union([padId]) { 
            if id < logits.count { logits[id] = -Float.infinity } 
        }
        
        // 1) repetition penalty (window 128)
        var freq: [Int:Int] = [:]
        for id in ids.suffix(128) { 
            freq[Int(id), default: 0] += 1 
        }
        for (i,c) in freq { 
            if i < logits.count {
                logits[i] /= pow(repPenalty, Float(c)) 
            }
        }
        
        // 2) early whitespace ban
        if earlyWS {
            for id in [198, 628, 220] { 
                if id < logits.count { logits[id] = -Float.infinity } 
            } // Ċ, ĊĊ, space
            print("🚫 Step \(step): Hard banned whitespace tokens 198, 628, 220")
        }
        
        // 3) punctuation cooldown
        if banPunctNow {
            for id in [11, 13, 25, 26, 8, 357] { 
                if id < logits.count { logits[id] = -Float.infinity } 
            } // , . : ; ) " ( 
            print("🚫 Step \(step): Banned punctuation due to recent punctuation")
        }
        
        // 4) true no-repeat-n-gram mask
        if ids.count >= noRepeatN - 1 {
            var seen: [ArraySlice<Int32>: Set<Int>] = [:]
            for i in 0..<(ids.count - (noRepeatN - 1)) {
                let prefix = ids[i..<(i + noRepeatN - 1)]
                let next = Int(ids[i + noRepeatN - 1])
                seen[prefix, default: []].insert(next)
            }
            let currentPrefix = ids.suffix(noRepeatN - 1)
            if let forbid = seen[currentPrefix] {
                for id in forbid { 
                    if id < logits.count { logits[id] = -Float.infinity } 
                }
                print("🚫 Step \(step): Blocked \(forbid.count) tokens due to n-gram repetition")
            }
        }
    }
    
    private func sampleNextToken(from row: UnsafeBufferPointer<Float>, step: Int, recentTokens: [Int32]) -> Int32 {
        // Derive actual size from the buffer we *really* have
        let count = row.count
        precondition(count > 0, "logits row is empty")
        
        // Safe copy: exactly the valid region
        var maskedLogits = Array(row)
        
        // Guard every index with the real length
        let n = maskedLogits.count
        precondition(n > 0, "maskedLogits is empty")
        
        // PAD mask (only if in range)
        if padId >= 0 && Int(padId) < n {
            maskedLogits[Int(padId)] = -Float.infinity
        }
        
        // Apply repetition penalty to recently used tokens (only to recent tokens, not globally)
        if repetitionPenalty > 1.0 {
            // Note: This will be implemented when we have access to the ids array
            print("🔧 Repetition penalty active: \(repetitionPenalty)")
        }
        

        
        // Apply all masks and penalties BEFORE sampling
        applyMasksAndPenalties(&maskedLogits, 
                              ids: recentTokens, 
                              step: step, 
                              padId: Int(padId), 
                              earlyWS: step < 10, 
                              banPunctNow: shouldBanPunctuation(recentTokens), 
                              noRepeatN: 3, 
                              repPenalty: repetitionPenalty, 
                              bannedSpecials: [Int(endCommentaryId), Int(endDevotionalId)])
        
        // Sanitize after masking/penalties: replace any non-finite values
        for i in maskedLogits.indices where !maskedLogits[i].isFinite {
            maskedLogits[i] = -Float.infinity
        }
        
        // Primer token bias for early steps (nudge into narrative mode)
        // Token 770 = "ĠThis" - common high-probability narrative starter
        if step < 3 {  // Only for first 2-3 steps after [START_COMMENTARY]
            if 770 < n { 
                maskedLogits[770] += 3.0  // Boost "ĠThis" 
                print("🚀 Step \(step): Boosted primer token 770 (ĠThis)")
            }
        }
        
        // Deterministic warm-up for early steps (greedy-ish to avoid newline spirals)
        if step < 4 {  // First 2-4 tokens after [START_COMMENTARY]
            var bestIdx = 0
            var bestVal = -Float.infinity
            for i in 0..<n { 
                let v = maskedLogits[i]; 
                if v > bestVal { bestVal = v; bestIdx = i } 
            }
            print("🎯 Step \(step): Deterministic warm-up, selected token \(bestIdx)")
            return Int32(bestIdx)
        }
        
        // Normal sampling for later steps
        if temperature == nil && topK == nil && topP == nil {
            var bestIdx = 0
            var bestVal = -Float.infinity
            for i in 0..<n { 
                let v = maskedLogits[i]; 
                if v > bestVal { bestVal = v; bestIdx = i } 
            }
            return Int32(bestIdx)
        }
        // Temperature + optional top-k / top-p
        let temp = max(1e-6, Double(temperature ?? 1.0))
        var indices = Array(0..<n)
        var scores = indices.map { Double(maskedLogits[$0]) / temp }
        // Top-k
        if let k = topK, k > 0, k < n {
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
    
    // Helper function to get top-k indices from logits
    private func topKIndices(from row: UnsafeBufferPointer<Float>, k: Int, vocab: Vocab?) -> [(id: Int, token: String, score: Float)] {
        let n = row.count
        var indices = Array(0..<n)
        let scores = Array(row)
        
        // Sort by score (descending) and take top k
        indices.sort { scores[$0] > scores[$1] }
        let topK = Array(indices.prefix(k))
        
        return topK.map { idx in
            let token = vocab?.idToToken[Int32(idx)] ?? "?"
            return (id: idx, token: token, score: scores[idx])
        }
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
        let currentVocabSize = logitsArray.shape[2].intValue

        // Clamp t to the produced length, not the input length.
        let t = max(0, min(currentLen - 1, Lout - 1))

        // Get a pointer (slice) to the last-step logits as Float
        let row: UnsafeBufferPointer<Float> = logitsArray.rowAsFloat(atTime: t, vocab: currentVocabSize)
        let chosen = sampleNextToken(from: row, step: 0, recentTokens: [])

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
                (startDevotionalId, "[START_DEVOTIONAL]"),
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
                // Note: We no longer compare against global vocabSize for bounds checking
                // The actual bounds are checked at runtime using the current row length
                if dims.count >= 3 {
                    print("✅ Model output shape check passed: \(dims)")
                }
            }
        }
        
        print("🔍 Integrity checks complete")
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
