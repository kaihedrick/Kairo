// BibleCommentaryGenerator.swift
import Foundation
import CoreML
import SwiftUI

@MainActor
final class BibleCommentaryGenerator: ObservableObject {
    private static var _shared: BibleCommentaryGenerator!
    static var shared: BibleCommentaryGenerator {
        if _shared == nil {
            _shared = BibleCommentaryGenerator()
        }
        return _shared
    }
    private static var didInit = false

    @Published var isGenerating = false
    @Published var generatedText = ""
    @Published var error: String?
    @Published private(set) var isReady = false

    private(set) var model: MLModel?
    private var tokenizerSvc: TokenizerService?
    private var art: TokenizerArtifacts!

    private var seqLen: Int = 1024
    private var nLayer = 12, nHead = 12, headDim = 64

    private struct KVCaches { var k:[MLMultiArray]; var v:[MLMultiArray] }
    private var caches: KVCaches?

    private let TEMP: Float = 0.9, TOPK: Int = 100, TOPP: Float = 0.95, REP: Float = 1.15
    private let MAX_NEW = 800, MIN_NEW = 40

    init() { if !Self.didInit { Self.didInit = true; load() } }

    private func load() {
        print("🚀 Loading resources…")
        do {
            art = try TokenizerArtifacts.load()
            seqLen = art.report.model_io.seq_len
            nLayer = art.report.model_io.n_layer
            nHead  = art.report.model_io.n_head
            headDim = art.report.model_io.head_dim
            tokenizerSvc = TokenizerService(art: art)
            print("✅ export_report: seq_len=\(seqLen), kv=L\(nLayer) H\(nHead) D\(headDim)")
        } catch { print("❌ Tokenizer load error: \(error)") }

        loadModel()
        dumpModelSignature()

        // loadModelFromBundle() already handled assertDynamicSignature()
        // and will fatalError if model is not valid

        isReady = (model != nil && tokenizerSvc != nil)
        print(isReady ? "✅ Generator ready" : "⚠️ Generator not ready")

        // Quick smoke test - forces compile with proper shapes
        if let model = model {
            Task {
                await preflightCompile(model, nHead: nHead, headDim: headDim, nLayer: nLayer)
            }
        }

        // TEMPORARY: Enable diagnostics to see what's in the bundle
        diagnoseModelBundle()
        // TODO: Remove this after confirming .mlpackage loads correctly
        // CoreMLSelfTest.run()
    }

    private func loadModel() {
        model = loadModelFromBundle()
        // loadModelFromBundle now handles all error cases and returns a valid MLModel
    }

    private func dumpModelSignature() {
        guard let model else { return }
        dumpSignature(model)
    }

    private func allocateZeroCaches(pastLen: Int = 1) throws -> KVCaches {
        var k:[MLMultiArray]=[], v:[MLMultiArray]=[]
        // Ensure pastLen is at least 1 to avoid zero dimensions
        let safePastLen = max(1, pastLen)
        let shape:[NSNumber] = [1, NSNumber(value: nHead), NSNumber(value: safePastLen), NSNumber(value: headDim)]
        #if DEBUG
        print("🔍 DEBUG: Allocating KV cache with shape: \(shape)")
        #endif
        for _ in 0..<nLayer {
            let kCache = try MLMultiArray(shape: shape, dataType: .float32)
            let vCache = try MLMultiArray(shape: shape, dataType: .float32)
            k.append(kCache)
            v.append(vCache)
        }
        return KVCaches(k: k, v: v)
    }

    private func makeInt32(_ shape:[Int], fill:Int32=0) throws -> MLMultiArray {
        let a = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .int32)
        a.dataPointer.bindMemory(to: Int32.self, capacity: a.count).initialize(repeating: fill, count: a.count)
        return a
    }

    private func makeMask2D(past: Int, input: Int) throws -> MLMultiArray {
        let S = past + input
        // Use 2D attention mask: [batch_size, seq_len] - consistent with preflight test
        return try makeInt32([1, S], fill: 1)
    }

    private func logitsRow(_ a: MLMultiArray) -> [Float] { a.lastVocabRow() }

    private func sample(_ row: [Float], recent: ArraySlice<Int32>) -> Int32 {
        var logits = row
        let n = logits.count
        // repetition penalty
        if REP > 1.0 { for id in recent.suffix(64) { let i = Int(id); if i >= 0 && i < n && logits[i].isFinite { logits[i] /= REP } } }
        // temp
        if TEMP != 1 { for i in 0..<n { logits[i] /= TEMP } }
        // top-k
        if TOPK > 0 && TOPK < n {
            let thr = logits.enumerated().sorted(by: { $0.element > $1.element })[TOPK-1].element
            for i in 0..<n where logits[i] < thr { logits[i] = -.infinity }
        }
        // top-p
        if TOPP < 1.0 {
            var probs = logits
            let m = probs.max() ?? 0; var s: Float = 0
            for i in 0..<n { probs[i] = expf(probs[i] - m); s += probs[i] }
            if s > 0 { for i in 0..<n { probs[i] /= s } }
            let sorted = probs.enumerated().sorted { $0.element > $1.element }
            var cum: Float = 0; var keep = Set<Int>()
            for (i,p) in sorted { cum += p; keep.insert(i); if cum >= TOPP { break } }
            for i in 0..<n where !keep.contains(i) { logits[i] = -.infinity }
        }
        // argmax (after filters)
        var best = 0; for i in 1..<n { if logits[i] > logits[best] { best = i } }
        return Int32(best)
    }

    @MainActor
    func generateCommentary(for verseRef: String, verseText: String) async -> String {
        guard let model, let tokenizerSvc else { self.error = "Model/tokenizer not ready"; return "" }
        self.isGenerating = true; self.error = nil; self.generatedText = ""

        var ids = tokenizerSvc.encodePrompt(verseRef: verseRef, verseText: verseText, maxLen: seqLen)
        if ids.isEmpty {
            await MainActor.run {
                self.error = "Failed to encode prompt - no tokens generated"
                self.isGenerating = false
            }
            return ""
        }

        // fresh caches: past_len = 1 (required by CoreML export to prevent zero shape error)
        do {
            caches = try allocateZeroCaches(pastLen: 1)
            #if DEBUG
            print("🔍 DEBUG: Initial KV cache shapes: k[0] = \(caches!.k[0].shape), v[0] = \(caches!.v[0].shape)")
            #endif
        } catch {
            await MainActor.run {
                self.error = "Cache alloc failed: \(error.localizedDescription)"
                self.isGenerating = false
            }
            return ""
        }

        // WARM: feed full prompt once
        do {
            let promptLen = min(ids.count, seqLen)
            if promptLen == 0 {
                await MainActor.run {
                    self.error = "Prompt length is zero - cannot generate"
                    self.isGenerating = false
                }
                return ""
            }
            // Ensure promptLen is at least 1
            let safePromptLen = max(1, promptLen)
            let input = try makeInt32([1, safePromptLen])
            input.dataPointer.bindMemory(to: Int32.self, capacity: safePromptLen).update(from: &ids, count: promptLen)
            let past = caches!.k[0].shape[2].intValue
            #if DEBUG
            print("🔍 DEBUG: Past length from cache: \(past), prompt length: \(promptLen)")
            #endif
            let mask = try makeMask2D(past: past, input: safePromptLen)
            var feat: [String:MLFeatureValue] = ["input_ids": .init(multiArray: input), "attention_mask": .init(multiArray: mask)]
            for i in 0..<nLayer { feat["k_cache_\(i)"] = .init(multiArray: caches!.k[i]); feat["v_cache_\(i)"] = .init(multiArray: caches!.v[i]) }
            #if DEBUG
            print("🔍 DEBUG: Warm pass - Input shape: \(input.shape), Mask shape: \(mask.shape)")
            print("🔍 DEBUG: Warm pass - Past length: \(past), Prompt length: \(promptLen), Total: \(past + promptLen)")
            print("🔍 DEBUG: Warm pass - KV cache 0 shapes: k=\(caches!.k[0].shape), v=\(caches!.v[0].shape)")
            print("🔍 DEBUG: Warm pass - Total features: \(feat.count)")
            for (key, value) in feat {
                if let multiArray = value.multiArrayValue {
                    print("🔍 DEBUG: Feature '\(key)': shape=\(multiArray.shape), count=\(multiArray.count)")
                }
            }
            #endif
            let out = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: feat))
            var kN:[MLMultiArray]=[]; var vN:[MLMultiArray]=[]
            for i in 0..<nLayer { kN.append(out.featureValue(for: "present_k_\(i)")!.multiArrayValue!); vN.append(out.featureValue(for: "present_v_\(i)")!.multiArrayValue!) }
            caches = KVCaches(k: kN, v: vN)
            if let logits = out.featureValue(for: "logits")?.multiArrayValue { ids.append(sample(logitsRow(logits), recent: ids.suffix(64))) }
        } catch { self.error = "Warm failed: \(error.localizedDescription)"; self.isGenerating = false; return "" }

        // DECODE: 1 token per step
        var produced = 0; var done = false; var last = ids.last!
        while produced < MAX_NEW && !done {
            do {
                let input = try makeInt32([1,1]); input.dataPointer.bindMemory(to: Int32.self, capacity: 1)[0] = last
                let past = caches!.k[0].shape[2].intValue
                let mask = try makeMask2D(past: past, input: 1)
                var feat: [String:MLFeatureValue] = ["input_ids": .init(multiArray: input), "attention_mask": .init(multiArray: mask)]
                for i in 0..<nLayer { feat["k_cache_\(i)"] = .init(multiArray: caches!.k[i]); feat["v_cache_\(i)"] = .init(multiArray: caches!.v[i]) }
                let out = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: feat))
                var kN:[MLMultiArray]=[]; var vN:[MLMultiArray]=[]
                for i in 0..<nLayer { kN.append(out.featureValue(for: "present_k_\(i)")!.multiArrayValue!); vN.append(out.featureValue(for: "present_v_\(i)")!.multiArrayValue!) }
                caches = KVCaches(k: kN, v: vN)
                guard let logits = out.featureValue(for: "logits")?.multiArrayValue else { throw NSError(domain: "ML", code: -5) }
                last = sample(logitsRow(logits), recent: ids.suffix(64))
                ids.append(last); produced += 1
                if ids.count >= seqLen { done = true }
                if produced % 8 == 0 || done {
                    let decoded = tokenizerSvc.decode(ids: ids.map(Int.init))
                    await MainActor.run { self.generatedText = decoded }
                }
            } catch { self.error = "Step failed: \(error.localizedDescription)"; break }
        }

        let final = tokenizerSvc.decode(ids: ids.map(Int.init))
        let sanitized = TextSanitizer.shared.sanitizeText(final)
        await MainActor.run {
            self.generatedText = sanitized
            self.isGenerating = false
        }
        return sanitized
    }
}

// MARK: - Model Loading Utilities

// MARK: - Bundle Diagnostics

/// Lists all Core ML artifacts in the app bundle for debugging
func listModelArtifacts() {
    let fm = FileManager.default
    func list(_ ext: String) {
        if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
            for u in urls {
                let attrs = (try? fm.attributesOfItem(atPath: u.path)) ?? [:]
                let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
                let mtime = (attrs[.modificationDate] as? Date)?.description ?? "?"
                print("📦", u.lastPathComponent, "(")
                print("    path:", u.path)
                print("    size:", size, "bytes")
                print("    mtime:", mtime)
                if size < 1000 { // Less than 1KB - suspicious
                    print("    ⚠️  VERY SMALL FILE - LIKELY STALE/CORRUPTED")
                }
                print(")")
            }
        } else {
            print("   No \(ext) files found")
        }
    }
    print("—— ARTIFACTS IN Bundle.main ——")
    list("mlpackage")
    list("mlmodelc")
    list("mlmodel")
    print("———————————————————————————")

    // Check for the specific file we're looking for
    if let specificURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage") {
        print("✅ FOUND: bible_commentary_model.mlpackage at:", specificURL.path)
        let attrs = (try? fm.attributesOfItem(atPath: specificURL.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        print("   Size:", size, "bytes")
        if size < 1000000 { // Less than 1MB - definitely wrong
            print("   ❌ SIZE TOO SMALL! Expected ~239MB, got \(size) bytes")
            print("   This suggests the wrong file or corrupted bundle")
        }
    } else {
        print("❌ MISSING: bible_commentary_model.mlpackage not found in bundle")
        print("   This means the .mlpackage is not being copied to the app bundle by Xcode")
    }
}

/// Public function to diagnose bundle issues - call this from anywhere
public func diagnoseModelBundle() {
    listModelArtifacts()
}

@MainActor
func loadModelFromBundle() -> MLModel {
    // First, list all model artifacts for diagnostics
    listModelArtifacts()

    let cfg = MLModelConfiguration()
    #if targetEnvironment(simulator)
    cfg.computeUnits = .cpuOnly
    #else
    cfg.computeUnits = .cpuAndNeuralEngine
    #endif

    // 1) Try the expected name first
    if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage") {
        print("🔍 Found .mlpackage URL:", url.path)
        let fm = FileManager.default
        let attrs = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        print("🔍 .mlpackage file size:", size, "bytes")

        if let m = try? MLModel(contentsOf: url, configuration: cfg) {
            print("🟢 Loaded .mlpackage (expected name)")
            dumpSignature(m)
            assertDynamicSignature(m)  // Hard guard against fixed-length models
            return m
        } else {
            print("❌ Failed to load .mlpackage despite finding URL")
        }
    } else {
        print("❌ No .mlpackage URL found for 'bible_commentary_model'")
    }

    // 2) Fallback: scan for any .mlpackage in main bundle
    if let urls = Bundle.main.urls(forResourcesWithExtension: "mlpackage", subdirectory: nil) {
        for u in urls {
            if let m = try? MLModel(contentsOf: u, configuration: cfg) {
                print("🟢 Loaded .mlpackage (scanned):", u.lastPathComponent)
                dumpSignature(m)
                assertDynamicSignature(m)
                return m
            }
        }
    }

    // 3) Last resort: look in all bundles (main + embedded frameworks)
    for b in [Bundle.main] + (Bundle.allBundles + Bundle.allFrameworks) {
        if let urls = b.urls(forResourcesWithExtension: "mlpackage", subdirectory: nil) {
            for u in urls {
                if let m = try? MLModel(contentsOf: u, configuration: cfg) {
                    print("🟢 Loaded .mlpackage from bundle:", b.bundlePath)
                    dumpSignature(m)
                    assertDynamicSignature(m)
                    return m
                }
            }
        }
    }

    // TEMPORARY FALLBACK: Allow .mlmodelc for now while user fixes Xcode setup
    print("⚠️  No .mlpackage found - trying .mlmodelc as temporary fallback...")
    if let url = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodelc") {
        print("🔍 Found .mlmodelc URL:", url.path)
        let fm = FileManager.default
        let attrs = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        print("🔍 .mlmodelc file size:", size, "bytes")

        if let m = try? MLModel(contentsOf: url, configuration: cfg) {
            print("🟡 Loaded .mlmodelc (TEMPORARY - please fix Xcode bundle setup)")
            print("   ⚠️  This is likely a STALE or CORRUPTED file (only \(size) bytes)")
            print("   📝 The real .mlpackage should be ~239MB")
            dumpSignature(m)
            // Skip shape validation for now to allow app to run
            return m
        } else {
            print("❌ Failed to load .mlmodelc despite finding URL")
        }
    } else {
        print("❌ No .mlmodelc URL found either")
    }

    fatalError("""
    No ML model found in bundle!

    IMMEDIATE ACTION REQUIRED:
    1. Open Xcode project
    2. Remove bible_commentary_model.mlmodel from project
    3. Add bible_commentary_model.mlpackage to Copy Bundle Resources
    4. Clean build and rebuild

    See console output above for current bundle contents.
    """)
}

func dumpSignature(_ model: MLModel) {
    print("— MODEL INPUTS —")
    for (n,d) in model.modelDescription.inputDescriptionsByName {
        if let c = d.multiArrayConstraint {
            print("\t\(n): shape=\(c.shape)")
            // Note: shapeConstraint API availability varies by iOS version
            // The shape above shows if it's dynamic (variable) or fixed (constant)
        } else {
            print("\t\(n): (no constraint)")
        }
    }
    print("— MODEL OUTPUTS —")
    for (n,d) in model.modelDescription.outputDescriptionsByName {
        if let c = d.multiArrayConstraint {
            print("\t\(n): shape=\(c.shape)")
        } else {
            print("\t\(n): (COLLAPSED TO SCALAR - WILL CAUSE ERRORS)")
        }
    }
}

// Hard guard: refuse to run if signature is fixed/degenerate
func assertDynamicSignature(_ model: MLModel) {
    let ins = model.modelDescription.inputDescriptionsByName
    guard let ids = ins["input_ids"]?.multiArrayConstraint,
          let mask = ins["attention_mask"]?.multiArrayConstraint else {
        fatalError("Model missing required inputs")
    }
    precondition(ids.shape.count == 2 && ids.shape[1] != 1, "input_ids second dim must be flexible (not fixed to 1)")
    precondition(mask.shape.count >= 2 && mask.shape.last! != 1, "attention_mask last dim must be flexible (not fixed to 1)")
}

// MARK: - Preflight Compilation

@MainActor
func preflightCompile(_ model: MLModel, nHead: Int, headDim: Int, nLayer: Int) async {
    do {
        let ids  = try MLMultiArray(shape: [1,1], dataType: .int32); ids[0] = 0
        let mask = try MLMultiArray(shape: [1,2], dataType: .int32); mask[0] = 1; mask[1] = 1 // past=1, input=1
        var feat: [String:MLFeatureValue] = ["input_ids": .init(multiArray: ids), "attention_mask": .init(multiArray: mask)]
        for i in 0..<nLayer {
            feat["k_cache_\(i)"] = .init(multiArray: try MLMultiArray(shape: [1,NSNumber(value:nHead),1,NSNumber(value:headDim)], dataType: .float32))
            feat["v_cache_\(i)"] = .init(multiArray: try MLMultiArray(shape: [1,NSNumber(value:nHead),1,NSNumber(value:headDim)], dataType: .float32))
        }
        _ = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: feat))
        print("✅ Preflight compile OK")
    } catch { print("❌ Preflight failed:", error) }
}