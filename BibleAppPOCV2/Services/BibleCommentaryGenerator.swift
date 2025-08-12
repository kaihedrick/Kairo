// filepath: BibleAppPOCV2/Services/BibleCommentaryGenerator.swift

import Foundation
import CoreML
import SwiftUI
import Accelerate

enum InferenceMode { case coreml, fallback }

@MainActor
final class BibleCommentaryGenerator: ObservableObject {
    // MARK: - Singleton
    static let shared = BibleCommentaryGenerator()
    private static var didInit = false

    // MARK: - UI state
    @Published var isGenerating = false
    @Published var generatedText = ""
    @Published var error: String?
    @Published private(set) var mode: InferenceMode = .fallback
    @Published private(set) var isReady = false

    // MARK: - Core objects
    private(set) var model: MLModel?
    private var vocab: Vocab?
    private var bpe: GPT2BPEEncoder?
    private(set) var outputName: String = "logits"

    private var loadTask: Task<Void, Error>?

    // MARK: - Sampling controls
    var temperature: Float? = 0.8
    var topK: Int? = 100
    var topP: Float? = 0.92
    var repetitionPenalty: Float = 1.15

    // MARK: - Model/tokenizer constants
    private var seqLen: Int = 512
    private let defaultVocabSize: Int = 50266

    // Special token IDs (authoritative: tokenizer_config.json)
    private var padId: Int32 = 50265
    private var endDevotionalId: Int32 = 50264
    private var endCommentaryId: Int32 = 50262
    private var startCommentaryId: Int32 = 50261
    private var startDevotionalId: Int32 = 50263
    private var verseId: Int32 = 50257
    private var verseRefId: Int32 = 50258
    private var verseTextId: Int32 = 50259
    private var verseTagId: Int32 = 50260

    private init() {
        guard !Self.didInit else { return }
        Self.didInit = true
        loadResources()
    }

    // MARK: - Public readiness gate
    func ready() async throws {
        if isReady { return }
        if let t = loadTask { return try await t.value }

        loadTask = Task {
            var spins = 0
            while !isReady && spins < 50 {
                try await Task.sleep(nanoseconds: 100_000_000)
                spins += 1
            }
        }

        do {
            try await loadTask!.value
        } catch {
            loadTask = nil
            throw error
        }
    }

    // MARK: - Resource loading
    private func loadResources() {
        print("🚀 Starting resource loading...")

        loadTokenizerConfig()
        loadVocab()
        loadBPE()
        parseExportReport()
        loadModel()
        performStartupValidation()

        if isReady {
            mode = .coreml
            NotificationCenter.default.post(name: .coreMLBibleModelReady, object: nil)
            print("✅ CoreML mode activated and notification sent")
        } else {
            mode = .fallback
            print("⚠️ Fallback mode activated due to validation failures")
        }

        print("🔍 Final state - BPE loaded: \(bpe != nil), Vocab loaded: \(vocab != nil), Model loaded: \(model != nil)")
    }

    private func resolveURL(name: String, ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/ML")
    }

    private func loadTokenizerConfig() {
        guard let url = resolveURL(name: "tokenizer_config", ext: "json") else {
            print("⚠️ tokenizer_config.json not found - using default special IDs")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            if let dec = json["added_tokens_decoder"] as? [String: [String: Any]] {
                for (k, v) in dec {
                    guard let id = Int32(k), let content = v["content"] as? String else { continue }
                    switch content {
                    case "[PAD]": padId = id
                    case "[END_DEVOTIONAL]": endDevotionalId = id
                    case "[END_COMMENTARY]": endCommentaryId = id
                    case "[START_COMMENTARY]": startCommentaryId = id
                    case "[START_DEVOTIONAL]": startDevotionalId = id
                    case "[VERSE_ID]": verseId = id
                    case "[VERSE_REF]": verseRefId = id
                    case "[VERSE_TEXT]": verseTextId = id
                    case "[VERSE]": verseTagId = id
                    default: break
                    }
                }
                print("✅ Loaded special token IDs from tokenizer_config.json")
            }
        } catch { print("❌ Failed to parse tokenizer_config.json: \(error)") }
    }

    private func loadVocab() {
        guard let url = resolveURL(name: "id_to_token", ext: "json") else {
            print("⚠️ id_to_token.json not found; decoding will be limited"); return
        }
        do {
            vocab = try Vocab.load(from: url)
            print("✅ Loaded id_to_token.json @ \(url.path)")
        } catch { print("❌ Failed loading id_to_token.json: \(error)") }
    }

    private func loadBPE() {
        bpe = GPT2BPEEncoder.shared
        if let bpe { print("✅ BPE tokenizer loaded (vocab count: \(bpe.vocabCount))") }
        else { print("⚠️ BPE tokenizer unavailable") }
    }

    private func parseExportReport() {
        guard let url = resolveURL(name: "export_report", ext: "json") else { return }
        do {
            let data = try Data(contentsOf: url)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let modelIO = obj["model_io"] as? [String: Any],
                   let seq = modelIO["seq_len"] as? Int {
                    seqLen = seq
                    print("✅ Updated seq_len from export_report: \(seq)")
                } else if let seq = obj["seq_len"] as? Int {
                    seqLen = seq
                    print("✅ Updated seq_len (legacy): \(seq)")
                }
            }
            print("🧾 export_report loaded from \(url.lastPathComponent)")
        } catch { print("⚠️ Failed to parse export_report.json: \(error)") }
    }

    private func loadModel() {
        do {
            let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
            cfg.computeUnits = .cpuOnly
#else
            cfg.computeUnits = .cpuAndNeuralEngine
#endif
            if let g = try? bible_commentary_model(configuration: cfg) {
                self.model = g.model
                print("🟢 Core ML generator ready (generated class)")
                return
            }
        }

        let exts = ["mlmodelc", "mlpackage", "mlmodel"]
        for ext in exts {
            if let url = resolveURL(name: "bible_commentary_model", ext: ext) {
                do {
                    let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
                    cfg.computeUnits = .cpuOnly
#else
                    cfg.computeUnits = .cpuAndNeuralEngine
#endif
                    if ext == "mlpackage" {
                        let compiled = try MLModel.compileModel(at: url)
                        self.model = try MLModel(contentsOf: compiled, configuration: cfg)
                    } else {
                        self.model = try MLModel(contentsOf: url, configuration: cfg)
                    }
                    print("🟢 Core ML generator ready (\(ext))")
                    return
                } catch { print("❌ Failed to load \(ext): \(error)") }
            }
        }
        print("❌ No Core ML model found in bundle")
    }

    private func performStartupValidation() {
        print("🔍 Performing startup validation...")
        guard let vocab else { print("❌ Vocab not loaded"); isReady = false; return }
        print("✅ Vocab size (loaded): \(vocab.idToToken.count)")
        guard seqLen > 0 else { print("❌ Invalid seq_len \(seqLen)"); isReady = false; return }
        print("✅ Sequence length: \(seqLen)")
        guard model != nil else { print("❌ Core ML model not loaded"); isReady = false; return }
        resolveOutputNameIfPossible()
        isReady = true
        print("✅ All startup validations passed - generator is ready")
    }

    private func resolveOutputNameIfPossible() {
        guard let mdl = model else { return }
        let outs = mdl.modelDescription.outputDescriptionsByName
        if outs["logits"] != nil { outputName = "logits"; return }
        if let anyMA = outs.first(where: { $0.value.multiArrayConstraint != nil })?.key {
            outputName = anyMA
            print("ℹ️ Using fallback output name: \(outputName)")
        }
    }

    // MARK: - Public generation API
    func generateCommentary(for verseRef: String, verseText: String) async -> String {
        guard !isGenerating else { return generatedText }
        isGenerating = true
        error = nil
        generatedText = ""

        guard let model = self.model else { self.error = "Model not loaded"; isGenerating = false; return "" }
        guard let vocab = self.vocab else { self.error = "Vocab not loaded"; isGenerating = false; return "" }
        guard let bpe = self.bpe else { self.error = "BPE assets not loaded"; isGenerating = false; return "" }

        let prompt = makePrompt(verseRef: verseRef, verseText: verseText)
        print("🧪 Prompt preview:\n\(prompt.prefix(200))")

        var ids = bpe.encode(prompt, maxLength: seqLen).map { Int32($0) }
        if ids.isEmpty { ids = [padId] }

        let L = seqLen
        var mask = [Int32](repeating: 0, count: L)
        let prefixLen = min(ids.count, L)
        if ids.count < L { ids += Array(repeating: padId, count: L - ids.count) }
        for i in 0..<prefixLen { mask[i] = 1 }

        let inputIds = try? makeInt32Array([1, L])
        let attnMask = try? makeInt32Array([1, L])
        guard let inputIds, let attnMask else {
            self.error = "Failed to allocate input buffers"; isGenerating = false; return ""
        }

        print("🔧 Initial setup: prefixLen=\(prefixLen), seqLen=\(L)")
        var currentLen = prefixLen
        var generated = 0
        let maxNew = 400

        while currentLen < L && generated < maxNew {
            fillInputBuffer(inputIds, with: ids, currentLen: currentLen, seqLen: L)
            fillMaskBuffer(attnMask, with: mask, currentLen: currentLen, seqLen: L)

            do {
                let provider = try MLDictionaryFeatureProvider(dictionary: [
                    "input_ids": MLFeatureValue(multiArray: inputIds),
                    "attention_mask": MLFeatureValue(multiArray: attnMask)
                ])

                // ✅ FIX: Core ML async API requires await
                let out = try await model.prediction(from: provider)

                var logitsArray = out.featureValue(for: outputName)?.multiArrayValue
                if logitsArray == nil {
                    for name in out.featureNames {
                        if let m = out.featureValue(for: name)?.multiArrayValue { logitsArray = m; break }
                    }
                }
                guard let logits = logitsArray else {
                    print("❌ No logits found in output"); break
                }

                let shape = logits.shape.map { $0.intValue }
                let v = max(1, shape.last ?? defaultVocabSize)
                let row = try readLogitsRow(logits, vocab: v)
                let next = sampleNextToken(from: row, vocab: v, step: generated,
                                           recentTokens: Array(ids.prefix(currentLen)))

                ids[currentLen] = next
                mask[currentLen] = 1
                currentLen += 1
                generated += 1

                if next == endDevotionalId { break }

                let partial = vocab.decode(ids: Array(ids.prefix(currentLen)))
                self.generatedText = partial
            } catch {
                self.error = "Prediction failed: \(error.localizedDescription)"
                break
            }
        }

        let finalText = vocab.decode(ids: Array(ids.prefix(currentLen)))
        print("✅ Generation complete: \(generated) new tokens (total \(currentLen))")
        self.generatedText = finalText
        self.isGenerating = false
        return finalText
    }

    // MARK: - Prompt
    private func makePrompt(verseRef: String, verseText: String) -> String {
        let id: String = {
            let comps = verseRef.split(separator: " ")
            guard comps.count >= 2 else { return verseRef.uppercased().replacingOccurrences(of: " ", with: "_") }
            let book = comps.dropLast().joined(separator: "_").uppercased()
            let chapVerse = comps.last!.replacingOccurrences(of: ":", with: "_")
            return "\(book)_\(chapVerse)"
        }()
        return """
        [VERSE_ID] \(id)
        [VERSE_REF] \(verseRef)
        [VERSE_TEXT] \(verseText)
        [VERSE]
        [START_COMMENTARY]
        """
    }

    // MARK: - Buffers
    private func makeInt32Array(_ shape: [Int], fill: Int32 = 0) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .int32)
        let total = shape.reduce(1, *)
        let base = UnsafeMutablePointer<Int32>(OpaquePointer(arr.dataPointer))
        base.initialize(repeating: fill, count: total)
        return arr
    }

    private func fillInputBuffer(_ buffer: MLMultiArray, with values: [Int32], currentLen: Int, seqLen: Int) {
        let base = UnsafeMutablePointer<Int32>(OpaquePointer(buffer.dataPointer))
        for i in 0..<min(currentLen, seqLen) { base[i] = values[i] }
        for i in currentLen..<seqLen { base[i] = padId }
    }

    private func fillMaskBuffer(_ buffer: MLMultiArray, with mask: [Int32], currentLen: Int, seqLen: Int) {
        let base = UnsafeMutablePointer<Int32>(OpaquePointer(buffer.dataPointer))
        for i in 0..<min(currentLen, seqLen) { base[i] = mask[i] }
        for i in currentLen..<seqLen { base[i] = 0 }
    }

    // MARK: - Safe logits reader
    @inline(__always) private func f16to32(_ h: UInt16) -> Float {
        let s = (h & 0x8000) != 0
        let e = Int((h & 0x7C00) >> 10)
        var f = Int(h & 0x03FF)
        if e == 0 {
            if f == 0 { return s ? -0.0 : 0.0 }
            var exp = -14
            while (f & 0x400) == 0 { f <<= 1; exp -= 1 }
            f &= 0x3FF
            let val = ldexpf(Float(f) / 1024.0 + 1.0, Int32(exp))
            return s ? -val : val
        } else if e == 31 {
            return s ? -.infinity : .infinity
        } else {
            let val = ldexpf(Float(f) / 1024.0 + 1.0, Int32(e - 15))
            return s ? -val : val
        }
    }

    private func readLogitsRow(_ logits: MLMultiArray, vocab expectedV: Int) throws -> [Float] {
        let shape = logits.shape.map { $0.intValue }
        let rank = shape.count
        guard (1...3).contains(rank) else {
            throw NSError(domain: "Logits", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected rank \(rank) for logits: \(shape)"])
        }
        let v = shape.last ?? expectedV
        let seq = (rank == 3 ? shape[1] : 1)
        let t = max(0, seq - 1)
        let baseOffset = (rank == 3 ? t * v : 0)

        switch logits.dataType {
        case .float32:
            let base = logits.dataPointer.bindMemory(to: Float.self, capacity: logits.count)
            return Array(UnsafeBufferPointer(start: base.advanced(by: baseOffset), count: v))
        case .float16:
            let src = logits.dataPointer.bindMemory(to: UInt16.self, capacity: logits.count)
            var out = [Float](repeating: 0, count: v)
            for i in 0..<v { out[i] = f16to32(src[baseOffset + i]) }
            return out
        default:
            throw NSError(domain: "Logits", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported dtype \(logits.dataType)"])
        }
    }

    // MARK: - Sampling
    private func sampleNextToken(
        from row: [Float],
        vocab v: Int,
        step: Int,
        recentTokens: [Int32]
    ) -> Int32 {
        let count = min(v, row.count)
        var logits = row

        if padId >= 0 && Int(padId) < count { logits[Int(padId)] = -.infinity }
        if step == 0, 198 < count { logits[198] = -.infinity }

        if repetitionPenalty > 1.0 {
            for id in recentTokens.suffix(64) {
                let i = Int(id)
                if i >= 0 && i < count, logits[i].isFinite { logits[i] /= repetitionPenalty }
            }
        }

        if let t = temperature, t > 0, t != 1 { for i in 0..<count { logits[i] /= t } }

        if let k = topK, k > 0 && k < count {
            let th = logits.enumerated().sorted(by: { $0.element > $1.element })[k - 1].element
            for i in 0..<count where logits[i] < th { logits[i] = -.infinity }
        }

        if let p = topP, p < 1.0 {
            let m = logits.prefix(count).max() ?? 0
            var exps = logits.prefix(count).map { expf($0 - m) }
            let total = exps.reduce(0, +)
            if total > 0 {
                for i in 0..<count { exps[i] /= total }
                let sorted = exps.enumerated().sorted(by: { $0.element > $1.element })
                var keep = Set<Int>(); var cum: Float = 0
                for (i, prob) in sorted { cum += prob; keep.insert(i); if cum >= p { break } }
                for i in 0..<count where !keep.contains(i) { logits[i] = -.infinity }
            }
        }

        let best = (0..<count).max(by: { logits[$0] < logits[$1] }) ?? 0
        return Int32(best)
    }
}

// MARK: - Commentary/Devotional Split Parser

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
    func generateCommentaryAndDevotional(for verseRef: String, verseText: String) async -> ParsedBibleContent {
        let raw = await generateCommentary(for: verseRef, verseText: verseText)
        return parseGeneratedContent(raw)
    }

    func parseGeneratedContent(_ text: String) -> ParsedBibleContent {
        var commentary = ""
        var devotional = ""

        if let s = text.range(of: "[START_COMMENTARY]"),
           let e = text.range(of: "[END_COMMENTARY]"),
           s.upperBound < e.lowerBound {
            commentary = String(text[s.upperBound..<e.lowerBound])
            print("✅ Found commentary section (\(commentary.count) chars)")
        }

        if let s = text.range(of: "[START_DEVOTIONAL]"),
           let e = text.range(of: "[END_DEVOTIONAL]"),
           s.upperBound < e.lowerBound {
            devotional = String(text[s.upperBound..<e.lowerBound])
            print("✅ Found devotional section (\(devotional.count) chars)")
        }

        if commentary.isEmpty && devotional.isEmpty {
            commentary = text
            print("⚠️ No special tokens found, treating entire text as commentary")
        }

        commentary = cleanSectionText(commentary)
        devotional = cleanSectionText(devotional)

        return ParsedBibleContent(commentary: commentary, devotional: devotional, rawText: text)
    }

    private func cleanSectionText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .replacingOccurrences(of: "  ", with: " ")
    }
}
