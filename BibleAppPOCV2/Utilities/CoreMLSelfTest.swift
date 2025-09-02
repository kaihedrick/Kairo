// filepath: BibleAppPOCV2/Utilities/CoreMLSelfTest.swift
import Foundation
import CoreML

enum CoreMLSelfTest {
    static func run() {
        let bundle = Bundle.main
        let cfg = MLModelConfiguration()
        #if targetEnvironment(simulator)
        cfg.computeUnits = .cpuOnly
        #else
        cfg.computeUnits = .cpuAndNeuralEngine
        #endif

        func url(_ ext: String) -> URL? { bundle.url(forResource: "bible_commentary_model", withExtension: ext) }

        print("🔎 CoreMLSelfTest — locating model …")
        print("• .mlmodelc:", url("mlmodelc")?.path ?? "nil")
        print("• .mlpackage:", url("mlpackage")?.path ?? "nil")
        print("• .mlmodel:", url("mlmodel")?.path ?? "nil")

        do {
            // Use same loading logic as main app - prefer .mlpackage only
            if let u = url("mlpackage") {
                let m = try MLModel(contentsOf: u, configuration: cfg)
                try describe(model: m)
                try quickForward(model: m)
                return
            }

            // Fallback to .mlmodelc if .mlpackage not found
            if let u = url("mlmodelc") {
                let m = try MLModel(contentsOf: u, configuration: cfg)
                try describe(model: m)
                try quickForward(model: m)
                return
            }

            // Last resort - try .mlmodel (not recommended)
            if let u = url("mlmodel") {
                let m = try MLModel(contentsOf: u, configuration: cfg)
                try describe(model: m)
                try quickForward(model: m)
                return
            }

            print("❌ CoreMLSelfTest — no model files found in bundle")
            print("   Make sure bible_commentary_model.mlpackage is in Copy Bundle Resources")
        } catch {
            print("❌ CoreMLSelfTest — load/forward error:", error.localizedDescription)
        }
    }

    private static func describe(model: MLModel) throws {
        let md = model.modelDescription
        let ins = md.inputDescriptionsByName.keys.sorted()
        let outs = md.outputDescriptionsByName.keys.sorted()
        print("✅ Loaded model")
        print("   Inputs:", ins)
        print("   Outputs:", outs)
        if !(outs.contains("logits") || outs.contains("linear_0")) {
            print("⚠️ Unexpected output names:", outs, "— will pick first 3D output at runtime")
        }
    }

    private static func quickForward(model: MLModel) throws {
        let seqLen = 8  // Small test sequence to avoid memory issues
        let nHead = 12  // From model config
        let headDim = 64 // From model config
        let nLayer = 12  // From model config

        // Create basic inputs
        let ids = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)
        let mask = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)

        // Fill with test data
        for i in 0..<seqLen {
            ids[i] = NSNumber(value: Int32(i % 100))  // Simple token IDs
            mask[i] = 1  // All positions are valid
        }

        var inputs: [String: MLFeatureValue] = [
            "input_ids": MLFeatureValue(multiArray: ids),
            "attention_mask": MLFeatureValue(multiArray: mask)
        ]

        // Add KV caches (required for our model)
        for i in 0..<nLayer {
            let kShape = [1, NSNumber(value: nHead), 1, NSNumber(value: headDim)]
            let vShape = [1, NSNumber(value: nHead), 1, NSNumber(value: headDim)]

            inputs["k_cache_\(i)"] = MLFeatureValue(multiArray: try MLMultiArray(shape: kShape, dataType: .float32))
            inputs["v_cache_\(i)"] = MLFeatureValue(multiArray: try MLMultiArray(shape: vShape, dataType: .float32))
        }

        let out = try model.prediction(from: try MLDictionaryFeatureProvider(dictionary: inputs))

        // Look for logits output
        if let logits = out.featureValue(for: "logits")?.multiArrayValue {
            print("✅ Quick forward ok — logits shape:", logits.shape)
        } else {
            print("⚠️ No logits output found in prediction result")
            let availableOutputs = out.featureNames.sorted()
            print("   Available outputs:", availableOutputs)
        }
    }
}


