// File: BibleAppPOCV2/Services/LLMService.swift
// Directory: Services
// Purpose: Send tokens to flan_t5_encoder.mlpackage and handle Core ML inference

import Foundation
import CoreML

class LLMService {
    private var model: MLModel?

    init() {
        loadModel()
    }

    private func loadModel() {
        // Try multiple approaches to find the model
        var modelURL: URL?
        
        // Approach 1: Try the original path
        if let url = Bundle.main.url(forResource: "flan_t5_encoder", withExtension: "mlpackage", subdirectory: "Resources/ML") {
            modelURL = url
            print("✅ Found model using subdirectory approach")
        }
        // Approach 2: Try without subdirectory
        else if let url = Bundle.main.url(forResource: "flan_t5_encoder", withExtension: "mlpackage") {
            modelURL = url
            print("✅ Found model using direct bundle approach")
        }
        // Approach 3: Try searching in the main bundle
        else if let url = Bundle.main.url(forResource: "flan_t5_encoder", withExtension: "mlpackage", subdirectory: nil) {
            modelURL = url
            print("✅ Found model using main bundle search")
        }
        // Approach 4: Try to find it in the app's resources
        else {
            print("🔍 Searching for model in bundle resources...")
            if let resourcePath = Bundle.main.resourcePath {
                let fileManager = FileManager.default
                if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                    while let file = enumerator.nextObject() as? String {
                        if file.contains("flan_t5_encoder") && file.hasSuffix(".mlpackage") {
                            let fullPath = (resourcePath as NSString).appendingPathComponent(file)
                            modelURL = URL(fileURLWithPath: fullPath)
                            print("✅ Found model at: \(fullPath)")
                            break
                        }
                    }
                }
            }
        }
        
        // Approach 5: Fallback - Copy from source to documents directory
        if modelURL == nil {
            print("🔧 Attempting fallback: Copying model from source to documents directory...")
            modelURL = copyModelToDocumentsDirectory()
        }
        
        // If we found a model, try to load it
        if let url = modelURL {
            do {
                // Check if this is a .mlpackage that needs compilation
                if url.pathExtension == "mlpackage" {
                    // Try to compile the model for the current platform
                    let compiledURL = try compileModelIfNeeded(at: url)
                    model = try MLModel(contentsOf: compiledURL)
                    print("✅ Core ML model compiled and loaded successfully from: \(compiledURL.path)")
                } else {
                    model = try MLModel(contentsOf: url)
                    print("✅ Core ML model loaded successfully from: \(url.path)")
                }
            } catch {
                print("❌ Failed to load Core ML model: \(error)")
            }
        } else {
            print("❌ flan_t5_encoder.mlpackage not found in any location")
            print("🔍 Available bundle resources:")
            if let resourcePath = Bundle.main.resourcePath {
                let fileManager = FileManager.default
                if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                    while let file = enumerator.nextObject() as? String {
                        if file.contains("mlpackage") || file.contains("ML") {
                            print("   - \(file)")
                        }
                    }
                }
            }
        }
    }
    
    private func copyModelToDocumentsDirectory() -> URL? {
        let fileManager = FileManager.default
        
        // Get the documents directory
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Could not access documents directory")
            return nil
        }
        
        let modelDestinationURL = documentsPath.appendingPathComponent("flan_t5_encoder.mlpackage")
        
        // Check if model already exists in documents directory
        if fileManager.fileExists(atPath: modelDestinationURL.path) {
            print("✅ Model already exists in documents directory")
            return modelDestinationURL
        }
        
        // Try to find the model in the source directory
        // The model is located at: ./BibleAppPOCV2/Resources/ML/flan_t5_encoder.mlpackage
        let possibleSourcePaths = [
            Bundle.main.bundlePath + "/../BibleAppPOCV2/Resources/ML/flan_t5_encoder.mlpackage",
            Bundle.main.bundlePath + "/../../BibleAppPOCV2/Resources/ML/flan_t5_encoder.mlpackage",
            Bundle.main.bundlePath + "/../../../BibleAppPOCV2/Resources/ML/flan_t5_encoder.mlpackage",
            // Add absolute path as fallback
            "/Users/jeffhedrick/Pictures/GitHub/BibleAppPOCV2/BibleAppPOCV2/Resources/ML/flan_t5_encoder.mlpackage"
        ]
        
        print("🔍 Searching for model in source directories...")
        for (index, sourcePath) in possibleSourcePaths.enumerated() {
            print("   Checking path \(index + 1): \(sourcePath)")
            if fileManager.fileExists(atPath: sourcePath) {
                print("✅ Found model at source: \(sourcePath)")
                
                do {
                    // Remove existing model if it exists
                    if fileManager.fileExists(atPath: modelDestinationURL.path) {
                        try fileManager.removeItem(at: modelDestinationURL)
                    }
                    
                    // Copy the model to documents directory
                    try fileManager.copyItem(atPath: sourcePath, toPath: modelDestinationURL.path)
                    print("✅ Successfully copied model to documents directory")
                    return modelDestinationURL
                } catch {
                    print("❌ Failed to copy model: \(error)")
                }
            } else {
                print("   ❌ Not found at: \(sourcePath)")
            }
        }
        
        print("❌ Could not find model in any source location")
        print("🔍 Current working directory: \(fileManager.currentDirectoryPath)")
        print("🔍 Bundle path: \(Bundle.main.bundlePath)")
        return nil
    }
    
    private func compileModelIfNeeded(at url: URL) throws -> URL {
        let fileManager = FileManager.default
        
        // Check if we already have a compiled version
        let compiledURL = url.deletingPathExtension().appendingPathExtension("mlmodelc")
        
        if fileManager.fileExists(atPath: compiledURL.path) {
            print("✅ Found existing compiled model at: \(compiledURL.path)")
            return compiledURL
        }
        
        print("🔧 Compiling model for current platform...")
        print("   Source: \(url.path)")
        print("   Target: \(compiledURL.path)")
        
        do {
            // Compile the model for the current platform
            let compiledModelURL = try MLModel.compileModel(at: url)
            print("✅ Model compiled successfully to: \(compiledModelURL.path)")
            return compiledModelURL
        } catch {
            print("❌ Failed to compile model: \(error)")
            throw error
        }
    }

    func encode(tokens: [Int]) -> [Float] {
        guard let model = model else {
            print("Core ML model not loaded")
            return []
        }
        
        // Handle empty tokens array - provide a default sequence
        let processedTokens: [Int]
        if tokens.isEmpty {
            print("⚠️ Empty tokens array, using default sequence")
            // Use a default sequence with PAD tokens (token ID 0 based on config)
            processedTokens = Array(repeating: 0, count: 8) // Model expects 8 tokens
        } else {
            processedTokens = tokens
        }
        
        // Ensure we have exactly 8 tokens (pad or truncate as needed)
        let finalTokens: [Int]
        if processedTokens.count > 8 {
            finalTokens = Array(processedTokens.prefix(8))
            print("⚠️ Truncated tokens from \(processedTokens.count) to 8")
        } else if processedTokens.count < 8 {
            finalTokens = processedTokens + Array(repeating: 0, count: 8 - processedTokens.count)
            print("⚠️ Padded tokens from \(processedTokens.count) to 8")
        } else {
            finalTokens = processedTokens
        }
        
        do {
            // Create input_ids array with shape [1, 8] (fixed size)
            let inputArray = try MLMultiArray(shape: [1, 8], dataType: .int32)
            for (i, token) in finalTokens.enumerated() {
                inputArray[i] = NSNumber(value: token)
            }
            
            // Create attention_mask array with shape [1, 8] (fixed size)
            let attentionMaskArray = try MLMultiArray(shape: [1, 8], dataType: .int32)
            for i in 0..<8 {
                // Set attention mask to 1 for real tokens, 0 for padding
                let attentionValue = i < processedTokens.count ? 1 : 0
                attentionMaskArray[i] = NSNumber(value: attentionValue)
            }
            
            // Create input dictionary with both required features
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: inputArray),
                "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
            ])
            
            print("🔍 Running Core ML inference with \(finalTokens.count) tokens...")
            print("   Input shape: [1, 8] (fixed)")
            print("   Token IDs: \(finalTokens)")
            let output = try model.prediction(from: input)
            
            // Try different possible output feature names
            var encoderOutput: MLMultiArray?
            let possibleOutputNames = ["encoder_output", "var_889", "hidden_states", "last_hidden_state"]
            
            for outputName in possibleOutputNames {
                if let outputFeature = output.featureValue(for: outputName)?.multiArrayValue {
                    encoderOutput = outputFeature
                    print("✅ Found encoder output in feature: \(outputName)")
                    break
                }
            }
            
            if let encoderOutput = encoderOutput {
                let result = (0..<encoderOutput.count).map { Float(truncating: encoderOutput[$0]) }
                print("✅ Core ML inference successful, output shape: \(encoderOutput.shape)")
                return result
            } else {
                print("❌ No encoder output found in model output")
                print("🔍 Available output features: \(output.featureNames)")
                
                // Try to use any available output as fallback
                if let firstOutput = output.featureNames.first,
                   let firstOutputFeature = output.featureValue(for: firstOutput)?.multiArrayValue {
                    let result = (0..<firstOutputFeature.count).map { Float(truncating: firstOutputFeature[$0]) }
                    print("⚠️ Using fallback output from feature: \(firstOutput)")
                    return result
                }
            }
        } catch {
            print("❌ Core ML inference failed: \(error)")
        }
        return []
    }
}

