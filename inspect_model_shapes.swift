#!/usr/bin/env swift

import Foundation
import CoreML

// Simple script to inspect Core ML model shapes
print("🔬 Core ML Model Shape Inspector")
print("===============================")

// Load the model
let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
cfg.computeUnits = .cpuOnly
#endif

func url(_ ext: String) -> URL? {
    // Try the simulator app bundle first
    let simulatorAppPath = "/Users/jeffhedrick/Library/Developer/CoreSimulator/Devices/9C56FB3C-A181-4CAB-94A9-DDECFAA41512/data/Containers/Bundle/Application/8DFDB591-0A0D-40CB-B02B-B3401BA71B05/BibleAppPOCV2.app/bible_commentary_model.\(ext)"

    if FileManager.default.fileExists(atPath: simulatorAppPath) {
        return URL(fileURLWithPath: simulatorAppPath)
    }

    // Fallback to project directory
    let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    // Try .mlpackage first
    if ext == "mlpackage" {
        let modelPath = currentDir.appendingPathComponent("BibleAppPOCV2/ML/Models/bible_commentary_model.mlpackage")
        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath
        }
    }

    // Try the .mlmodel inside the .mlpackage
    if ext == "mlmodel" {
        let modelPath = currentDir.appendingPathComponent("BibleAppPOCV2/ML/Models/bible_commentary_model.mlpackage/Data/com.apple.CoreML/model.mlmodel")
        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath
        }
    }

    return nil
}

print("📁 Looking for model files...")
print("• .mlmodelc:", url("mlmodelc")?.path ?? "nil")
print("• .mlpackage:", url("mlpackage")?.path ?? "nil")
print("• .mlmodel:", url("mlmodel")?.path ?? "nil")

do {
    var model: MLModel?

    // Try .mlmodelc first (compiled model from simulator)
    if let u = url("mlmodelc") {
        print("📦 Loading .mlmodelc...")
        model = try MLModel(contentsOf: u, configuration: cfg)
        print("✅ Loaded from .mlmodelc")
    } else if let u = url("mlmodel") {
        print("📦 Loading .mlmodel...")
        model = try MLModel(contentsOf: u, configuration: cfg)
        print("✅ Loaded from .mlmodel")
    } else if let u = url("mlpackage") {
        print("📦 Loading .mlpackage...")
        model = try MLModel(contentsOf: u, configuration: cfg)
        print("✅ Loaded from .mlpackage")
    }

    guard let model = model else {
        print("❌ No model files found")
        exit(1)
    }

    // Inspect the model
    let description = model.modelDescription

    print("\n🔬 === CORE ML MODEL INSPECTION ===")

    print("\n📥 INPUT FEATURES:")
    for (name, feature) in description.inputDescriptionsByName {
        if let constraint = feature.multiArrayConstraint {
            print("  - \(name):")
            print("    Shape: \(constraint.shape.map { $0.intValue })")
            print("    DataType: \(constraint.dataType)")
            if name.hasPrefix("k_cache_") || name.hasPrefix("v_cache_") {
                print("    🎯 KV CACHE INPUT: \(name)")
                let expectedShape = constraint.shape.map { $0.intValue }
                print("      Expected shape: \(expectedShape)")
            }
        }
    }

    print("\n📤 OUTPUT FEATURES:")
    for (name, feature) in description.outputDescriptionsByName {
        if let constraint = feature.multiArrayConstraint {
            print("  - \(name):")
            print("    Shape: \(constraint.shape.map { $0.intValue })")
            print("    DataType: \(constraint.dataType)")
            if name.hasPrefix("present_k_") || name.hasPrefix("present_v_") {
                print("    🎯 KV CACHE OUTPUT: \(name)")
                let outputShape = constraint.shape.map { $0.intValue }
                print("      Output shape: \(outputShape)")
            }
        }
    }

    print("\n🔍 === CURRENT SWIFT ALLOCATION ===")
    print("Swift currently allocates KV caches with:")
    print("  Shape: [1, 12, 1, 64] (batch_size=1, n_head=12, past_len=1, head_dim=64)")
    print("  DataType: float32")

    // Check for specific KV cache shape mismatch
    if let firstKCacheFeature = description.inputDescriptionsByName["k_cache_0"],
       let kCacheConstraint = firstKCacheFeature.multiArrayConstraint {
        let expectedShape = kCacheConstraint.shape.map { $0.intValue }
        let currentShape = [1, 12, 1, 64] // What Swift allocates

        print("\n📏 KV CACHE SHAPE COMPARISON:")
        print("   Expected by Core ML: \(expectedShape)")
        print("   Currently allocating: \(currentShape)")

        if expectedShape != currentShape {
            print("   🚨 SHAPE MISMATCH DETECTED!")
            print("   This will cause broadcast errors during inference")
            print("   Core ML expects: \(expectedShape)")
            print("   Swift allocates: \(currentShape)")

            // Provide specific fix
            print("\n🔧 RECOMMENDED FIX:")
            if expectedShape.count == 4 {
                print("   Change allocateZeroCaches() to use shape:")
                print("   [\(expectedShape[0]), \(expectedShape[1]), \(expectedShape[2]), \(expectedShape[3])]")
            }
        } else {
            print("   ✅ Shapes match")
        }
    }

    print("\n🔬 === END INSPECTION ===")

} catch {
    print("❌ Error: \(error.localizedDescription)")
}
