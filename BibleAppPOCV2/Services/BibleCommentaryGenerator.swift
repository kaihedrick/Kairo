// BibleCommentaryGenerator.swift
import Foundation
import CoreML
import SwiftUI

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

    private var seqLen: Int = 1536 // 512 encoder + 1024 decoder
    private let inputSeqLen = 512
    private let outputSeqLen = 1024

    // Special tokens from training script
    private let EOS_TOKEN_ID: Int32 = 50256
    private var verseRefId: Int32?
    private var verseTextId: Int32?
    private var verseId: Int32?
    private var startCommentaryId: Int32?
    private var endCommentaryId: Int32?
    private var startDevotionalId: Int32?
    private var endDevotionalId: Int32?
    private var padId: Int32?

    private var vocabSize: Int = 50399

    init() {
        if !Self.didInit {
            Self.didInit = true
            Task { await load() }
        }
    }

    @MainActor private func load() {
        print("🚀 Loading resources…")

        // Debug: Check if tokenizer files exist in bundle
        let tokenizerFiles = ["vocab.json", "merges.txt", "id_to_token.json",
                              "added_tokens.json", "export_report.json"]
        for fileName in tokenizerFiles {
            if let url = Bundle.main.url(forResource: fileName, withExtension: "",
                                         subdirectory: "ML/Models/ios_integration_assets") {
                print("✅ Found \(fileName) in bundle: \(url.path)")
            } else {
                print("❌ Missing \(fileName) in bundle")
            }
        }

        do {
            // Load artifacts using proper bundle loading
            art = try TokenizerArtifacts.load()
            tokenizer = GPT2BPETokenizer(vocab: art.tokenToId,
                                         merges: art.merges,
                                         idToToken: art.idToToken)

            // Load all special tokens from training script
            verseRefId        = art.addedTokens["[VERSE_REF]"].map(Int32.init)
            verseTextId       = art.addedTokens["[VERSE_TEXT]"].map(Int32.init)
            verseId           = art.addedTokens["[VERSE]"].map(Int32.init)
            startCommentaryId = art.addedTokens["[START_COMMENTARY]"].map(Int32.init)
            endCommentaryId   = art.addedTokens["[END_COMMENTARY]"].map(Int32.init)
            startDevotionalId = art.addedTokens["[START_DEVOTIONAL]"].map(Int32.init)
            endDevotionalId   = art.addedTokens["[END_DEVOTIONAL]"].map(Int32.init)
            padId             = art.addedTokens["[PAD]"].map(Int32.init)

            vocabSize = art.tokenToId.count
            seqLen    = art.report.model_io.seq_len

            print("✅ Tokenizer loaded with vocab=\(vocabSize), seqLen=\(seqLen)")
            print("🎯 Special tokens loaded:")
            print("  [VERSE_REF]: \(String(describing: verseRefId))")
            print("  [VERSE_TEXT]: \(String(describing: verseTextId))")
            print("  [VERSE]: \(String(describing: verseId))")
            print("  [START_COMMENTARY]: \(String(describing: startCommentaryId))")
            print("  [END_COMMENTARY]: \(String(describing: endCommentaryId))")
            print("  [START_DEVOTIONAL]: \(String(describing: startDevotionalId))")
            print("  [END_DEVOTIONAL]: \(String(describing: endDevotionalId))")
            print("  [PAD]: \(String(describing: padId))")

        } catch {
            print("❌ Tokenizer load error: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }

        // Load Core ML model using BundleLoader
        let cfg = MLModelConfiguration()
        #if targetEnvironment(simulator)
        cfg.computeUnits = .cpuOnly
        #else
        cfg.computeUnits = .cpuAndNeuralEngine
        #endif

        // Try to load Core ML model using proper bundle loading
        do {
            let modelURL = try BundleLoader.require(name: "bible_commentary_model", ext: "mlpackage")
            model = try MLModel(contentsOf: modelURL, configuration: cfg)
            print("🟢 Core ML model loaded successfully from: \(modelURL.path)")
        } catch {
            print("❌ Failed to load .mlpackage: \(error.localizedDescription)")

            // Fallback to .mlmodelc
            do {
                let modelURL = try BundleLoader.require(name: "bible_commentary_model", ext: "mlmodelc")
                model = try MLModel(contentsOf: modelURL, configuration: cfg)
                print("🟢 Core ML model loaded successfully from: \(modelURL.path)")
            } catch {
                print("❌ Failed to load .mlmodelc: \(error.localizedDescription)")
                self.error = "Failed to load Core ML model: \(error.localizedDescription)"
            }
        }

        isReady = (model != nil && tokenizer != nil)
        print(isReady ? "✅ Generator ready" : "⚠️ Generator not ready")
    }

    // MARK: - Helpers
    private func makeInt32Array(_ shape:[Int], fill:Int32=0) throws -> MLMultiArray {
        let a = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .int32)
        a.dataPointer.bindMemory(to: Int32.self, capacity: a.count)
            .initialize(repeating: fill, count: a.count)
        return a
    }

    /// Prepare input prompt for commentary generation (Phase 1)
    /// Matches training script format exactly
    private func prepareCommentaryPrompt(for verseRef: String, verseText: String) throws -> [Int] {
        guard let verseRefId = verseRefId,
              let verseTextId = verseTextId,
              let verseId = verseId,
              let startCommentaryId = startCommentaryId else {
            throw NSError(domain: "BibleCommentaryGenerator", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Missing required special tokens"])
        }

        // Exact format from training script:
        // [VERSE_REF] {verse_ref}\n[VERSE_TEXT] {verse_text}\n[VERSE]\n[START_COMMENTARY]
        let verseRefToken = tokenizer!.encode("[VERSE_REF]").first!
        let verseTextToken = tokenizer!.encode("[VERSE_TEXT]").first!
        let verseToken = tokenizer!.encode("[VERSE]").first!
        let startCommentaryToken = tokenizer!.encode("[START_COMMENTARY]").first!

        // Encode verse reference and text
        let verseRefIds = tokenizer!.encode(" \(verseRef)")
        let verseTextIds = tokenizer!.encode(" \(verseText)")

        // Build complete input: [VERSE_REF] {verse_ref} [VERSE_TEXT] {verse_text} [VERSE] [START_COMMENTARY]
        var ids: [Int] = []
        ids.append(verseRefToken)
        ids.append(contentsOf: verseRefIds)
        ids.append(verseTextToken)
        ids.append(contentsOf: verseTextIds)
        ids.append(verseToken)
        ids.append(startCommentaryToken)

        if ids.count > inputSeqLen {
            ids = Array(ids.suffix(inputSeqLen))
        }

        print("🔍 Commentary prompt tokens: \(ids.count)")
        return ids
    }

    /// Prepare input prompt for devotional generation (Phase 2)
    /// Matches training continuation format
    private func prepareDevotionalPrompt(commentaryText: String) throws -> [Int] {
        guard let startDevotionalId = startDevotionalId else {
            throw NSError(domain: "BibleCommentaryGenerator", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Missing [START_DEVOTIONAL] token"])
        }

        // Format: {commentary_output}\n[START_DEVOTIONAL]
        let startDevotionalToken = tokenizer!.encode("[START_DEVOTIONAL]").first!

        // Encode commentary text and add devotional start token
        var ids = tokenizer!.encode(commentaryText + "\n")
        ids.append(startDevotionalToken)

        if ids.count > inputSeqLen {
            ids = Array(ids.suffix(inputSeqLen))
        }

        print("🔍 Devotional prompt tokens: \(ids.count)")
        return ids
    }

    private func createPaddedInputs(ids: [Int]) throws -> (MLMultiArray, MLMultiArray) {
        print("🔧 Creating input arrays with seqLen: \(seqLen), input tokens: \(ids.count)")

        let arr  = try makeInt32Array([1, seqLen])
        let mask = try makeInt32Array([1, seqLen])

        let base = arr.dataPointer.bindMemory(to: Int32.self, capacity: seqLen)
        let maskBase = mask.dataPointer.bindMemory(to: Int32.self, capacity: seqLen)

        let padToken: Int32 = padId ?? 50265  // Use [PAD] token from assets or fallback
        print("🔧 Using pad token: \(padToken)")

        for i in 0..<ids.count {
            base[i] = Int32(ids[i])
            maskBase[i] = 1
        }
        for i in ids.count..<seqLen {
            base[i] = padToken
            maskBase[i] = 0
        }

        print("🔧 Input shape: \(arr.shape), Mask shape: \(mask.shape)")
        return (arr, mask)
    }

    private func performPrediction(inputIds: MLMultiArray,
                                   mask: MLMultiArray) async throws -> MLMultiArray {
        let feat: [String: MLFeatureValue] = [
            "input_ids": .init(multiArray: inputIds),
            "attention_mask": .init(multiArray: mask)
        ]
        let provider = try MLDictionaryFeatureProvider(dictionary: feat)
        let out = try await model!.prediction(from: provider)
        guard let logits = out.featureValue(for: outputName)?.multiArrayValue else {
            throw NSError(domain: "BibleCommentaryGenerator", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No logits in output"])
        }
        return logits
    }

    /// Sample tokens with proper stopping criteria for staged generation
    private func sampleTokens(from logits: MLMultiArray, stopTokens: [Int32], maxTokens: Int = 512) -> [Int] {
        var out: [Int] = []
        let start = inputSeqLen
        let end = min(inputSeqLen + maxTokens, logits.shape[1].intValue)

        for pos in start..<end {
            let row = logits.logitsRow(at: pos)
            guard !row.isEmpty else { continue }
            let nextId = row.indices.max(by: { row[$0] < row[$1] }) ?? 0

            // Stop if we hit any of the stop tokens
            if stopTokens.contains(Int32(nextId)) || nextId == Int(EOS_TOKEN_ID) {
                break
            }
            out.append(nextId)
        }
        return out
    }

    private func decode(_ ids: [Int]) async -> String {
        let text = tokenizer!.decode(ids)
        return await MainActor.run {
            TextSanitizer.shared.sanitizeText(text)
        }
    }

    // MARK: - Public Seq-to-Seq Generation
    func generateCommentary(for verseRef: String, verseText: String) async -> String {
        await MainActor.run { isGenerating = true; error = nil; generatedText = "" }

        do {
            print("🚀 Starting seq-to-seq generation for: \(verseRef)")
            print("📖 Verse text: \(verseText)")
            print("🎯 Special tokens status:")
            print("  - [START_COMMENTARY]: \(startCommentaryId != nil ? "Available (\(startCommentaryId!))" : "MISSING")")
            print("  - [END_COMMENTARY]: \(endCommentaryId != nil ? "Available (\(endCommentaryId!))" : "MISSING")")
            print("  - [START_DEVOTIONAL]: \(startDevotionalId != nil ? "Available (\(startDevotionalId!))" : "MISSING")")
            print("  - [END_DEVOTIONAL]: \(endDevotionalId != nil ? "Available (\(endDevotionalId!))" : "MISSING")")

            // Phase 1: Generate Commentary
            print("📝 Phase 1: Generating commentary...")
            let commentaryPromptIds = try prepareCommentaryPrompt(for: verseRef, verseText: verseText)
            let (inputIds1, mask1) = try createPaddedInputs(ids: commentaryPromptIds)
            let logits1 = try await performPrediction(inputIds: inputIds1, mask: mask1)

            // Stop at [END_COMMENTARY] or EOS
            guard let endCommentaryId = endCommentaryId else {
                throw NSError(domain: "BibleCommentaryGenerator", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Missing [END_COMMENTARY] token"])
            }

            let commentaryIds = sampleTokens(from: logits1, stopTokens: [endCommentaryId], maxTokens: 512)
            let commentaryText = tokenizer!.decode(commentaryIds)

            print("📊 Commentary generation stats:")
            print("  - Token count: \(commentaryIds.count)")
            print("  - Character count: \(commentaryText.count)")

            // Clean up commentary text (remove stop token if present)
            var cleanCommentary = commentaryText
            if cleanCommentary.contains("[END_COMMENTARY]") {
                cleanCommentary = cleanCommentary.components(separatedBy: "[END_COMMENTARY]").first ?? cleanCommentary
            }

            print("✅ Commentary generated: \(cleanCommentary.prefix(100))...")
            print("📝 FULL COMMENTARY:")
            print("==================")
            print(cleanCommentary)
            print("==================")

            // Phase 2: Generate Devotional
            print("🙏 Phase 2: Generating devotional...")
            let devotionalPromptIds = try prepareDevotionalPrompt(commentaryText: cleanCommentary)
            let (inputIds2, mask2) = try createPaddedInputs(ids: devotionalPromptIds)
            let logits2 = try await performPrediction(inputIds: inputIds2, mask: mask2)

            // Stop at [END_DEVOTIONAL] or EOS
            guard let endDevotionalId = endDevotionalId else {
                throw NSError(domain: "BibleCommentaryGenerator", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Missing [END_DEVOTIONAL] token"])
            }

            let devotionalIds = sampleTokens(from: logits2, stopTokens: [endDevotionalId], maxTokens: 512)
            let devotionalText = tokenizer!.decode(devotionalIds)

            print("📊 Devotional generation stats:")
            print("  - Token count: \(devotionalIds.count)")
            print("  - Character count: \(devotionalText.count)")

            // Clean up devotional text (remove stop token if present)
            var cleanDevotional = devotionalText
            if cleanDevotional.contains("[END_DEVOTIONAL]") {
                cleanDevotional = cleanDevotional.components(separatedBy: "[END_DEVOTIONAL]").first ?? cleanDevotional
            }

            print("✅ Devotional generated: \(cleanDevotional.prefix(100))...")
            print("🙏 FULL DEVOTIONAL:")
            print("==================")
            print(cleanDevotional)
            print("==================")

            // Combine results
            let finalText = cleanCommentary + "\n\n" + cleanDevotional

            print("📄 RAW GENERATED CONTENT (before sanitization):")
            print("===============================================")
            print(finalText)
            print("===============================================")

            let finalSanitized = await MainActor.run {
                TextSanitizer.shared.sanitizeText(finalText)
            }

            print("📖 FINAL SANITIZED CONTENT:")
            print("===========================")
            print(finalSanitized)
            print("===========================")

            print("📊 Final content stats:")
            print("  - Raw character count: \(finalText.count)")
            print("  - Sanitized character count: \(finalSanitized.count)")
            print("  - Sanitization reduced content by: \(finalText.count - finalSanitized.count) characters")

            await MainActor.run {
                generatedText = finalSanitized
                isGenerating = false
            }

            print("🎯 Seq-to-seq generation complete!")
            return finalSanitized

        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isGenerating = false
            }
            print("❌ Generation failed: \(error.localizedDescription)")
            return ""
        }
    }

    // MARK: - Public
    func inspectModelShapes() {
        guard let model else {
            print("❌ No model available for inspection")
            return
        }

        print("🔬 Model Input/Output Shapes:")
        print("Input features:")
        for input in model.modelDescription.inputDescriptionsByName {
            print("  \(input.key): \(input.value)")
            if let constraint = input.value.multiArrayConstraint {
                print("    Constraint: \(constraint)")
                print("    Shape: \(constraint.shape)")
                print("    Data type: \(constraint.dataType)")
            }
        }

        print("Output features:")
        for output in model.modelDescription.outputDescriptionsByName {
            print("  \(output.key): \(output.value)")
            if let constraint = output.value.multiArrayConstraint {
                print("    Constraint: \(constraint)")
                print("    Shape: \(constraint.shape)")
                print("    Data type: \(constraint.dataType)")
            }
        }

        print("Model metadata:")
        let metadata = model.modelDescription.metadata
        for (key, value) in metadata {
            print("  \(key): \(value)")
        }

        print("Model description:")
        print("  \(model.modelDescription)")
    }
}
