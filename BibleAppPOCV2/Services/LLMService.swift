// File: BibleAppPOCV2/Services/LLMService.swift
// Directory: Services
// Purpose: Send tokens to FlanT5Encoder.mlpackage and handle Core ML inference
// File: BibleAppPOCV2/Services/LLMService.swift
// Directory: Services
// Purpose: Send tokens to FlanT5Encoder.mlpackage and handle Core ML inference

import Foundation
import CoreML

import Foundation
import CoreML

class LLMService {
    private var model: MLModel?

    init() {
        loadModel()
    }

    private func loadModel() {
        guard let url = Bundle.main.url(forResource: "FlanT5Encoder", withExtension: "mlpackage", subdirectory: "Resources/ML") else {
            print("FlanT5Encoder.mlpackage not found in Resources/ML")
            return
        }
        do {
            model = try MLModel(contentsOf: url)
        } catch {
            print("Failed to load Core ML model: \(error)")
        }
    }

    func encode(tokens: [Int]) -> [Float] {
        guard let model = model else {
            print("Core ML model not loaded")
            return []
        }
        do {
            let inputArray = try MLMultiArray(shape: [NSNumber(value: tokens.count)], dataType: .int32)
            for (i, token) in tokens.enumerated() {
                inputArray[i] = NSNumber(value: token)
            }
            let input = try MLDictionaryFeatureProvider(dictionary: ["input_ids": inputArray])
            let output = try model.prediction(from: input)
            if let encoderOutput = output.featureValue(for: "encoder_output")?.multiArrayValue {
                return (0..<encoderOutput.count).map { Float(truncating: encoderOutput[$0]) }
            }
        } catch {
            print("Core ML inference failed: \(error)")
        }
        return []
    }
}
    // TODO: Integrate FlanT5Encoder.mlpackage using Core ML
    // This should accept token IDs and return encoder outputs
    func encode(tokens: [Int]) -> [Float] {
        // Placeholder: Simulate encoder output
        // Replace with actual Core ML model inference
        return tokens.map { Float($0) * 0.1 }
    }

