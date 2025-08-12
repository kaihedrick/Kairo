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
            // Prefer generated class if available
            if let mdl = try? bible_commentary_model(configuration: cfg) {
                try describe(model: mdl.model)
                try quickForward(model: mdl.model)
                return
            }

            if let u = url("mlmodelc") {
                let m = try MLModel(contentsOf: u, configuration: cfg)
                try describe(model: m)
                try quickForward(model: m)
                return
            }
            if let u = url("mlpackage") {
                let compiled = try MLModel.compileModel(at: u)
                let m = try MLModel(contentsOf: compiled, configuration: cfg)
                try describe(model: m)
                try quickForward(model: m)
                return
            }
            if let u = url("mlmodel") {
                let m = try MLModel(contentsOf: u, configuration: cfg)
                try describe(model: m)
                try quickForward(model: m)
                return
            }
            print("❌ CoreMLSelfTest — none of the model files were found in bundle")
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
        let seqLen = 512
        let ids = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)
        let mask = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)

        let names = model.modelDescription.inputDescriptionsByName.keys
        let inputs: [String: MLFeatureValue]
        if names.contains("input_ids") && names.contains("attention_mask") {
            inputs = [
                "input_ids": MLFeatureValue(multiArray: ids),
                "attention_mask": MLFeatureValue(multiArray: mask)
            ]
        } else {
            inputs = [
                "attention_mask": MLFeatureValue(multiArray: mask),
                "input_ids": MLFeatureValue(multiArray: ids)
            ]
        }

        let out = try model.prediction(from: try MLDictionaryFeatureProvider(dictionary: inputs))
        let key = out.featureNames.first {
            if let arr = out.featureValue(for: $0)?.multiArrayValue { return arr.shape.count == 3 }
            return false
        } ?? "logits"
        guard let logits = out.featureValue(for: key)?.multiArrayValue else {
            print("⚠️ Prediction result has no 3D logits-like output"); return
        }
        print("✅ Quick forward ok — logits shape:", logits.shape)
    }
}


