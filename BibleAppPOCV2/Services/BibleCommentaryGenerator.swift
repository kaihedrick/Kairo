// BibleCommentaryGenerator.swift
import Foundation
import CoreML
import SwiftUI

@MainActor
final class BibleCommentaryGenerator: ObservableObject {
    static let shared = BibleCommentaryGenerator()
    private static var didInit = false

    @Published var isGenerating = false
    @Published var generatedText = ""
    @Published var error: String?
    @Published private(set) var isReady = false

    private(set) var model: MLModel?
    private var tokenizer: GPT2BPETokenizer?
    private var art: TokenizerArtifacts!
    private var outputName: String = "logits"

    private var seqLen: Int = 1024
    private var nLayer = 12, nHead = 12, headDim = 64

    private let TEMP: Float = 0.9, TOPK: Int = 100, TOPP: Float = 0.95, REP: Float = 1.15
    private let MAX_NEW = 800, MIN_NEW = 40

    init() {
        if !Self.didInit {
            Self.didInit = true
            load()
        }
    }

    private func load() {
        print("🚀 Loading resources…")
        do {
            art = try TokenizerArtifacts.load()
            seqLen = art.report.model_io.seq_len
            nLayer = art.report.model_io.n_layer
            nHead  = art.report.model_io.n_head
            headDim = art.report.model_io.head_dim
            tokenizer = GPT2BPETokenizer(vocab: art.tokenToId, merges: art.merges, idToToken: art.idToToken)
            print("✅ export_report: seq_len=\(seqLen), kv=L\(nLayer) H\(nHead) D\(headDim)")
        } catch {
            print("❌ Tokenizer load error: \(error)")
        }

        let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
        cfg.computeUnits = .cpuOnly
#else
        cfg.computeUnits = .cpuAndNeuralEngine
#endif

        // Debug: Check all possible model file locations
        print("🔍 DEBUG: Searching for bible_commentary_model...")
        let mlpackageURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage")
        let mlmodelcURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodelc")
        let mlmodelURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodel")

        print("🔍 DEBUG: mlpackage URL: \(mlpackageURL?.path ?? "nil")")
        print("🔍 DEBUG: mlmodelc URL: \(mlmodelcURL?.path ?? "nil")")
        print("🔍 DEBUG: mlmodel URL: \(mlmodelURL?.path ?? "nil")")

        // Only try the bundle .mlpackage or .mlmodelc
        if let url = mlpackageURL ?? mlmodelcURL {
            print("🔍 DEBUG: Attempting to load model from: \(url.path)")
            do {
                model = try MLModel(contentsOf: url, configuration: cfg)
                print("🟢 Core ML model loaded successfully from bundle: \(url.lastPathComponent)")
                print("🟢 DEBUG: Model description: \(model!.modelDescription)")
            } catch {
                print("❌ Failed to load Core ML model: \(error)")
                print("❌ DEBUG: Error details: \(error.localizedDescription)")
                model = nil
            }
        } else {
            print("❌ Core ML model not found in bundle")
            print("❌ DEBUG: Bundle path: \(Bundle.main.bundlePath)")
            print("❌ DEBUG: Bundle URL: \(Bundle.main.bundleURL)")

            // List all files in the bundle to see what's available
            do {
                let bundleContents = try FileManager.default.contentsOfDirectory(atPath: Bundle.main.bundlePath)
                let mlFiles = bundleContents.filter { $0.contains("bible_commentary") || $0.contains(".ml") }
                print("❌ DEBUG: ML-related files in bundle: \(mlFiles)")
            } catch {
                print("❌ DEBUG: Failed to list bundle contents: \(error)")
            }
        }

        isReady = (model != nil && tokenizer != nil)
        print(isReady ? "✅ Generator ready" : "⚠️ Generator not ready")

        // Notify GenerationRuntime that CoreML is ready
        if isReady {
            GenerationRuntime.shared.switchToCoreML()
        }
    }



    private func makeInt32Array(_ shape:[Int], fill:Int32=0) throws -> MLMultiArray {
        let a = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .int32)
        a.dataPointer.bindMemory(to: Int32.self, capacity: a.count).initialize(repeating: fill, count: a.count)
        return a
    }



    private func logitsRow(_ a: MLMultiArray) -> [Float] { a.lastVocabRow() }

    private func sample(_ row: [Float], recent: ArraySlice<Int32>) -> Int32 {
        var logits = row
        let n = logits.count

        // repetition penalty
        if REP > 1.0 {
            for id in recent.suffix(64) {
                let i = Int(id)
                if i >= 0 && i < n && logits[i].isFinite {
                    logits[i] /= REP
                }
            }
        }

        // temp
        if TEMP != 1 {
            for i in 0..<n { logits[i] /= TEMP }
        }

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

        // argmax
        var best = 0
        for i in 1..<n { if logits[i] > logits[best] { best = i } }
        return Int32(best)
    }

    // 🎯 SINGLE-PASS: Classification-style generation (no autoregression)
    // This model predicts the "next token" for the entire input sequence at once
    // It's designed for scoring/classification, not full autoregressive text generation
    @MainActor
    func generateCommentary(for verseRef: String, verseText: String) async -> String {
        guard let model, let tokenizer else {
            self.error = "Model/tokenizer not ready"
            return ""
        }
        self.isGenerating = true
        self.error = nil
        self.generatedText = ""

        // Encode full prompt (verse reference + verse text)
        let prompt = "\(verseRef) \(verseText)"
        let ids = tokenizer.encode(prompt)
        if ids.isEmpty {
            self.isGenerating = false
            return ""
        }

        // Create input_ids array [1, seq_len]
        let arr = try? makeInt32Array([1, ids.count])
        if let base = arr?.dataPointer.bindMemory(to: Int32.self, capacity: ids.count) {
            for i in 0..<ids.count { base[i] = Int32(ids[i]) }
        }

        // Create attention_mask array [1, seq_len] (all 1s)
        let mask = try? makeInt32Array([1, ids.count], fill: 1)

        let feat: [String: MLFeatureValue] = [
            "input_ids": .init(multiArray: arr!),
            "attention_mask": .init(multiArray: mask!)
        ]

        // SINGLE Core ML prediction call (no autoregression)
        guard let out = try? await model.prediction(from: MLDictionaryFeatureProvider(dictionary: feat)),
              let logits = out.featureValue(for: outputName)?.multiArrayValue else {
            self.error = "Prediction failed"
            self.isGenerating = false
            return ""
        }

        // Get logits for the predicted "next token" (classification-style)
        let row = logitsRow(logits)
        let recentTokens = ids.suffix(64).map(Int32.init)
        let nextId = sample(row, recent: recentTokens[...])

        // Decode original input + predicted next token
        let finalIds = ids + [Int(nextId)]
        let final = tokenizer.decode(finalIds)
        self.generatedText = TextSanitizer.shared.sanitizeText(final)

        self.isGenerating = false
        return self.generatedText
    }

    // Inspect model input/output shapes for debugging
    func inspectModelShapes() {
        guard let model else {
            print("❌ No model available for inspection")
            return
        }

        print("🔬 Model Input/Output Shapes:")
        print("Input features:")
        for input in model.modelDescription.inputDescriptionsByName {
            print("  \(input.key): \(input.value)")
        }

        print("Output features:")
        for output in model.modelDescription.outputDescriptionsByName {
            print("  \(output.key): \(output.value)")
        }

        print("Model metadata:")
        let metadata = model.modelDescription.metadata
        for (key, value) in metadata {
            print("  \(key): \(value)")
        }
    }
}
