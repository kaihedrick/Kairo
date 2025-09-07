// BibleCommentaryGenerator.swift
import Foundation
import CoreML
import SwiftUI

<<<<<<< HEAD
=======
@MainActor
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
final class BibleCommentaryGenerator: ObservableObject {
    static let shared = BibleCommentaryGenerator()
    private static var didInit = false

<<<<<<< HEAD
    // Workaround for Swift compiler actor isolation crash
    // Using simple properties without actor isolation
=======
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
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

<<<<<<< HEAD
    // EOS token ID from tokenizer_config.json (<|endoftext|>)
    private let EOS_TOKEN_ID: Int32 = 50256

    // Structured stop tokens loaded from added_tokens.json
    private var endCommentaryId: Int32?
    private var endDevotionalId: Int32?
    private var startCommentaryId: Int32?

    // Derived vocab size (instead of hardcoding)
    private var vocabSize: Int = 50399

    init() {
        if !Self.didInit {
            Self.didInit = true
            Task { await load() }
        }
    }

    @MainActor private func load() {
        print("🚀 Loading resources…")

        // Debug: Check if tokenizer files exist in bundle (they should be copied during build)
        let tokenizerFiles = ["vocab.json", "merges.txt", "id_to_token.json", "added_tokens.json", "export_report.json"]
        for fileName in tokenizerFiles {
            if let url = Bundle.main.url(forResource: fileName, withExtension: "") {
                print("✅ Found \(fileName) in bundle: \(url.path)")
            } else {
                print("❌ Missing \(fileName) in bundle")
            }
        }

        do {
            print("🔍 DEBUG: Attempting to load TokenizerArtifacts...")
            art = try TokenizerArtifacts.load()
            print("🔍 DEBUG: TokenizerArtifacts loaded successfully")
            print("🔍 DEBUG: idToToken count: \(art.idToToken.count)")
            print("🔍 DEBUG: tokenToId count: \(art.tokenToId.count)")
            print("🔍 DEBUG: merges count: \(art.merges.count)")
            print("🔍 DEBUG: addedTokens count: \(art.addedTokens.count)")

            // Load structured tokens for proper generation control
            // Use nil instead of 0 to avoid false positives with real token ID 0
            startCommentaryId = art.addedTokens["[START_COMMENTARY]"].map(Int32.init)
            endCommentaryId = art.addedTokens["[END_COMMENTARY]"].map(Int32.init)
            endDevotionalId = art.addedTokens["[END_DEVOTIONAL]"].map(Int32.init)

            // Derive vocab size programmatically instead of hardcoding
            vocabSize = art.tokenToId.count
            print("🎯 Derived vocab size from artifacts: \(vocabSize)")

            print("🎯 Loaded structured tokens:")
            print("🎯 [START_COMMENTARY] ID: \(startCommentaryId.map(String.init) ?? "not found")")
            print("🎯 [END_COMMENTARY] ID: \(endCommentaryId.map(String.init) ?? "not found")")
            print("🎯 [END_DEVOTIONAL] ID: \(endDevotionalId.map(String.init) ?? "not found")")

=======
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
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
            seqLen = art.report.model_io.seq_len
            nLayer = art.report.model_io.n_layer
            nHead  = art.report.model_io.n_head
            headDim = art.report.model_io.head_dim
            tokenizer = GPT2BPETokenizer(vocab: art.tokenToId, merges: art.merges, idToToken: art.idToToken)
            print("✅ export_report: seq_len=\(seqLen), kv=L\(nLayer) H\(nHead) D\(headDim)")
<<<<<<< HEAD
            print("✅ Tokenizer loaded with \(art.tokenToId.count) tokens, \(art.merges.count) merges")
        } catch {
            print("❌ Tokenizer load error: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            if let nsError = error as? NSError {
                print("❌ NSError domain: \(nsError.domain), code: \(nsError.code)")
                print("❌ NSError userInfo: \(nsError.userInfo)")
            }
=======
        } catch {
            print("❌ Tokenizer load error: \(error)")
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
        }

        let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
        cfg.computeUnits = .cpuOnly
#else
        cfg.computeUnits = .cpuAndNeuralEngine
#endif

        // Debug: Check all possible model file locations
        print("🔍 DEBUG: Searching for bible_commentary_model...")
<<<<<<< HEAD

        // First, try the subdirectory (where the source .mlpackage lives)
        let mlpackageURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage", subdirectory: "ML/Models/ios_integration_assets")
        let mlmodelcURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodelc", subdirectory: "ML/Models/ios_integration_assets")
        let mlmodelURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodel", subdirectory: "ML/Models/ios_integration_assets")

        print("🔍 DEBUG: Subdirectory search - mlpackage URL: \(mlpackageURL?.path ?? "nil")")
        print("🔍 DEBUG: Subdirectory search - mlmodelc URL: \(mlmodelcURL?.path ?? "nil")")
        print("🔍 DEBUG: Subdirectory search - mlmodel URL: \(mlmodelURL?.path ?? "nil")")

        // Fallback: Also try root bundle (where Xcode might place the compiled .mlmodelc)
        let rootMlmodelcURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodelc")
        let rootMlmodelURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodel")

        print("🔍 DEBUG: Root bundle search - mlmodelc URL: \(rootMlmodelcURL?.path ?? "nil")")
        print("🔍 DEBUG: Root bundle search - mlmodel URL: \(rootMlmodelURL?.path ?? "nil")")

        // Try subdirectory first, then root bundle as fallback
        if let url = mlpackageURL ?? mlmodelcURL ?? rootMlmodelcURL ?? rootMlmodelURL {
=======
        let mlpackageURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage")
        let mlmodelcURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodelc")
        let mlmodelURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodel")

        print("🔍 DEBUG: mlpackage URL: \(mlpackageURL?.path ?? "nil")")
        print("🔍 DEBUG: mlmodelc URL: \(mlmodelcURL?.path ?? "nil")")
        print("🔍 DEBUG: mlmodel URL: \(mlmodelURL?.path ?? "nil")")

        // Only try the bundle .mlpackage or .mlmodelc
        if let url = mlpackageURL ?? mlmodelcURL {
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
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

<<<<<<< HEAD
        let wasReady = self.isReady
        let newReadyState = (model != nil && tokenizer != nil)
        self.isReady = newReadyState
        print(newReadyState ? "✅ Generator ready" : "⚠️ Generator not ready")

        // Post notification if readiness state changed
        if wasReady != newReadyState {
            print("📡 BibleCommentaryGenerator: Readiness changed from \(wasReady) to \(newReadyState)")
            NotificationCenter.default.post(
                name: GenerationRuntime.runtimeModeChangedNotification,
                object: self,
                userInfo: [GenerationRuntime.runtimeModeKey: newReadyState ? InferenceMode.coreml : InferenceMode.fallback]
            )
=======
        isReady = (model != nil && tokenizer != nil)
        print(isReady ? "✅ Generator ready" : "⚠️ Generator not ready")

        // Notify GenerationRuntime that CoreML is ready
        if isReady {
            GenerationRuntime.shared.switchToCoreML()
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
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

<<<<<<< HEAD
    // 🎯 SINGLE-PASS: CoreML Forward Pass with [1, N] input -> [1, N, modelVocabSize] logits
    // This model performs a single forward pass and predicts logits for every position
    // We use the logits from the last position to sample the next token
    // MARK: - Helper Functions for generateCommentary

    private func prepareInput(for verseRef: String, verseText: String) throws -> (ids: [Int], prompt: String) {
        // Create base prompt
        let basePrompt = "\(verseRef) \(verseText)"
        print("📝 Original prompt: \(basePrompt.prefix(100))...")

        // Encode the base prompt first
        var ids = tokenizer!.encode(basePrompt)

        if ids.isEmpty {
            throw NSError(domain: "BibleCommentaryGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode input"])
        }

        // Insert [START_COMMENTARY] token ID numerically if available
        if let sid = startCommentaryId {
            ids.insert(Int(sid), at: 0)  // prepend the actual special token ID
            print("🎯 Prepended [START_COMMENTARY] token ID: \(sid)")
        } else {
            print("⚠️ No [START_COMMENTARY] token ID available; proceeding without it")
        }

        // Truncate to fit 512 input token window (model expects 512 input + 1024 output = 1536 total)
        let inputSeqLen = 512
        if ids.count > inputSeqLen {
            let truncatedCount = ids.count - inputSeqLen
            ids = Array(ids.suffix(inputSeqLen))
            print("⚠️ Truncated input from \(ids.count + truncatedCount) to \(inputSeqLen) tokens to fit input window")
        }

        print("📝 Final input sequence length: \(ids.count) tokens")
        print("📝 Input IDs preview: \(ids.prefix(10))...")

        return (ids, basePrompt)
    }

    private func createPaddedInputs(ids: [Int]) throws -> (inputIds: MLMultiArray, attentionMask: MLMultiArray) {
        // Model expects 512 input tokens + 1024 output tokens = 1536 total seq_len
        // But we only have ids.count tokens, so we pad input to 512 tokens
        let totalSeqLen = seqLen       // 1536 from export_report.json
        let inputSeqLen = 512          // Fixed input sequence length
        let actualInputLen = ids.count

        print("🔍 DEBUG: Model expects \(inputSeqLen) input + 1024 output = \(totalSeqLen) total")
        print("🔍 DEBUG: We have \(actualInputLen) input tokens, will pad to \(inputSeqLen)")

        // Create padded input_ids array [1, totalSeqLen]
        let arr = try makeInt32Array([1, totalSeqLen])
        let base = arr.dataPointer.bindMemory(to: Int32.self, capacity: totalSeqLen)
        // Copy actual input tokens (up to 512)
        for i in 0..<min(actualInputLen, inputSeqLen) {
            base[i] = Int32(ids[i])
        }
        // Pad with PAD token (from export_report.json) up to 512
        let padTokenId: Int32 = 50265  // PAD token
        for i in actualInputLen..<inputSeqLen {
            base[i] = padTokenId
        }
        // The rest (512-1535) should remain 0 or PAD - model will generate there
        for i in inputSeqLen..<totalSeqLen {
            base[i] = padTokenId
        }

        // Create padded attention_mask array [1, totalSeqLen]
        // 1s for actual tokens (0 to min(actualInputLen, 512)), 0s for padding
        let mask = try makeInt32Array([1, totalSeqLen], fill: 0)  // Start with all 0s
        let maskBase = mask.dataPointer.bindMemory(to: Int32.self, capacity: totalSeqLen)
        // Set 1s for actual input tokens (up to 512)
        for i in 0..<min(actualInputLen, inputSeqLen) {
            maskBase[i] = 1
        }
        // Positions 512+ remain 0 (model generates output here)

        print("🔍 DEBUG: Padded input_ids to \(totalSeqLen) tokens (\(actualInputLen) real + \(inputSeqLen - actualInputLen) pad)")
        print("🔍 DEBUG: Attention mask has \(min(actualInputLen, inputSeqLen)) active positions")

        return (arr, mask)
    }

    private func performPrediction(inputIds: MLMultiArray, attentionMask: MLMultiArray) async throws -> MLMultiArray {
        let feat: [String: MLFeatureValue] = [
            "input_ids": .init(multiArray: inputIds),
            "attention_mask": .init(multiArray: attentionMask)
        ]

        // SINGLE Core ML prediction call (no autoregression)
        print("🔍 DEBUG: Making CoreML prediction with:")
        print("🔍 DEBUG: input_ids shape: \(inputIds.shape)")
        print("🔍 DEBUG: attention_mask shape: \(attentionMask.shape)")
        print("🔍 DEBUG: Model seq_len: \(seqLen)")

        let provider = try MLDictionaryFeatureProvider(dictionary: feat)
        let out = try await model!.prediction(from: provider)
        guard let logits = out.featureValue(for: outputName)?.multiArrayValue else {
            throw NSError(domain: "BibleCommentaryGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Prediction failed"])
        }

        print("🎯 Logits shape: \(logits.shape)")
        print("🎯 Logits count: \(logits.count)")

        return logits
    }

    private func sampleTokens(from logits: MLMultiArray, inputIds: [Int]) -> [Int] {
        // CORRECTED: Greedy decoding for seq2seq model (no autoregressive sampling)
        // The model has already generated the entire output sequence in one forward pass
        let actualInputLen = inputIds.count     // Original input length (~128)
        let inputSeqLen = 512                   // Input sequence boundary
        let outputSeqLen = 1024                 // Output sequence length
        var generatedIds: [Int] = []

        // Debug: Check model output shape
        print("🎯 Seq2Seq greedy decoding:")
        print("🎯 Input length: \(actualInputLen), Output starts at: \(inputSeqLen)")
        print("🎯 Logits shape: \(logits.shape)")

        // Take argmax from each output position (greedy decoding)
        let startPosition = inputSeqLen
        let maxAvailablePosition = logits.shape[1].intValue - 1
        let maxOutputPosition = inputSeqLen + outputSeqLen - 1
        let endPosition = min(startPosition + MAX_NEW, maxAvailablePosition + 1, maxOutputPosition + 1)

        print("🎯 Greedy decoding positions \(startPosition) to \(endPosition - 1)")

        for position in startPosition..<endPosition {
            let row = logits.logitsRow(at: position)
            if row.isEmpty {
                print("⚠️ No logits available for position \(position)")
                break
            }

            // GREEDY DECODING: Take the highest probability token (no sampling)
            let maxIndex = row.indices.max(by: { row[$0] < row[$1] })!
            let nextId = Int(maxIndex)

            print("🎯 Position \(position): Greedy argmax ID: \(nextId) (prob: \(row[maxIndex]))")

            // Check for structured stop tokens (structured markers first, then EOS)
            var stopReason = ""
            if let endCommentaryId = endCommentaryId, nextId == endCommentaryId {
                stopReason = "[END_COMMENTARY]"
            } else if let endDevotionalId = endDevotionalId, nextId == endDevotionalId {
                stopReason = "[END_DEVOTIONAL]"
            } else if nextId == EOS_TOKEN_ID {
                stopReason = "<|endoftext|>"
            }

            if !stopReason.isEmpty {
                print("🎯 Stop token reached: \(stopReason) (ID: \(nextId)), stopping generation")
                break
            }

            generatedIds.append(nextId)

            // Stop if we have enough content (at least MIN_NEW tokens)
            if generatedIds.count >= MIN_NEW {
                // Check if we have meaningful content by looking for special tokens
                let hasCommentaryMarkers = generatedIds.contains(Int(art.addedTokens["[START_COMMENTARY]"] ?? 0))
                if hasCommentaryMarkers {
                    print("🎯 Found commentary markers, continuing to generate more content")
                }
            }
        }

        print("🎯 Greedy decoding completed: \(generatedIds.count) tokens")
        return generatedIds
    }

    private func decodeAndSanitize(generatedIds: [Int]) async -> String {
        if generatedIds.isEmpty {
            return ""
        }

        let final = tokenizer!.decode(generatedIds)
        print("🔍 DEBUG: Generated text before sanitization: '\(final)'")
        print("🔍 DEBUG: Generated text length: \(final.count)")

        let sanitized = await TextSanitizer.shared.sanitizeText(final)
        print("🔍 DEBUG: Sanitized generated text: '\(sanitized)'")
        print("🔍 DEBUG: Sanitized text length: \(sanitized.count)")

        return sanitized
    }

    func generateCommentary(for verseRef: String, verseText: String) async -> String {
        // Initialize state on main actor
        await MainActor.run {
            self.isGenerating = true
            self.error = nil
            self.generatedText = ""
        }

        do {
            // Step 1: Prepare input
            let (ids, prompt) = try prepareInput(for: verseRef, verseText: verseText)

            // Step 2: Create padded inputs
            let (inputIds, attentionMask) = try createPaddedInputs(ids: ids)

            // Step 3: Perform prediction
            let logits = try await performPrediction(inputIds: inputIds, attentionMask: attentionMask)

            // Step 4: Sample tokens
            let generatedIds = sampleTokens(from: logits, inputIds: ids)

            // Step 5: Decode and sanitize
            let sanitized = await decodeAndSanitize(generatedIds: generatedIds)

            // Update state on main actor
            await MainActor.run {
                if sanitized.isEmpty {
                    self.error = "No tokens generated"
                } else {
                    self.generatedText = sanitized
                }
                print("✅ Generation completed successfully")
                self.isGenerating = false
            }

            return sanitized

        } catch {
            // Handle errors on main actor
            await MainActor.run {
                self.error = error.localizedDescription
                self.isGenerating = false
            }
            return ""
        }
=======
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
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
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
