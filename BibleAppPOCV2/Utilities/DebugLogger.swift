// filepath: BibleAppPOCV2/Utilities/DebugLogger.swift
import Foundation
import CoreML

// MARK: - CoreML Debug Utilities
class CoreMLDebugger {
    
    // MARK: - Model Inspection
    static func inspectModel(_ model: MLModel, name: String = "Model") {
        print("🔍 === \(name) INSPECTION ===")
        
        let description = model.modelDescription
        
        // Input features
        print("📥 Input Features:")
        for (name, feature) in description.inputDescriptionsByName {
            print("  - \(name):")
            if let multiArrayConstraint = feature.multiArrayConstraint {
                print("    Shape: \(multiArrayConstraint.shape)")
                print("    DataType: \(multiArrayConstraint.dataType)")
                print("    IsOptional: \(feature.isOptional)")
            }
        }
        
        // Output features
        print("📤 Output Features:")
        for (name, feature) in description.outputDescriptionsByName {
            print("  - \(name):")
            if let multiArrayConstraint = feature.multiArrayConstraint {
                print("    Shape: \(multiArrayConstraint.shape)")
                print("    DataType: \(multiArrayConstraint.dataType)")
                print("    IsOptional: \(feature.isOptional)")
            }
        }
        
        print("🔍 === END \(name) INSPECTION ===")
    }
    
    // MARK: - Input Validation
    static func validateInput(_ input: MLMultiArray, expectedShape: [Int], expectedDataType: MLMultiArrayDataType, name: String) -> Bool {
        print("🔍 === VALIDATING \(name) ===")
        
        let actualShape = input.shape.map { $0.intValue }
        let actualDataType = input.dataType
        
        print("📏 Expected shape: \(expectedShape)")
        print("📏 Actual shape: \(actualShape)")
        print("📏 Expected dataType: \(expectedDataType)")
        print("📏 Actual dataType: \(actualDataType)")
        
        // Check shape
        let shapeMatch = actualShape == expectedShape
        print("✅ Shape match: \(shapeMatch)")
        
        // Check data type
        let dataTypeMatch = actualDataType == expectedDataType
        print("✅ DataType match: \(dataTypeMatch)")
        
        // Check for data type conversion issues
        if !dataTypeMatch {
            print("⚠️ DATA TYPE MISMATCH DETECTED!")
            print("   This could cause CoreML to silently cast values, leading to token corruption")
            
            // Check if this is Int32 vs Float32 issue
            if (expectedDataType == .int32 && actualDataType == .float32) ||
               (expectedDataType == .float32 && actualDataType == .int32) {
                print("🚨 CRITICAL: Int32/Float32 mismatch detected!")
                print("   This is a known cause of single letter output in CoreML models")
                print("   CoreML will silently cast Int32 to Float32, corrupting token IDs")
            }
        }
        
        // Sample values for debugging
        print("🔍 Sample values:")
        let sampleCount = min(10, input.count)
        for i in 0..<sampleCount {
            let value = input[i]
            print("   [\(i)]: \(value) (type: \(type(of: value)))")
        }
        
        print("🔍 === END VALIDATING \(name) ===")
        return shapeMatch && dataTypeMatch
    }
    
    // MARK: - Logits Analysis
    static func analyzeLogits(_ logits: MLMultiArray) {
        print("🔍 === LOGITS ANALYSIS ===")
        
        let shape = logits.shape
        print("📊 Logits shape: \(shape)")
        print("📊 Logits dataType: \(logits.dataType)")
        
        guard shape.count == 3 else {
            print("❌ Unexpected logits shape: \(shape)")
            return
        }
        
        let sequenceLength = shape[1].intValue
        let vocabSize = shape[2].intValue
        
        print("📊 Sequence length: \(sequenceLength)")
        print("📊 Vocab size: \(vocabSize)")
        
        // Analyze first few positions
        let positionsToAnalyze = min(5, sequenceLength)
        
        for position in 0..<positionsToAnalyze {
            print("🔍 Position \(position) analysis:")
            
            var logitsForPosition: [Float] = []
            for vocabIndex in 0..<vocabSize {
                let logitIndex = position * vocabSize + vocabIndex
                let logitValue = Float(logits[logitIndex].floatValue)
                logitsForPosition.append(logitValue)
            }
            
            // Check for logits collapse
            let uniqueLogits = Set(logitsForPosition)
            print("   Unique logit values: \(uniqueLogits.count)")
            
            if uniqueLogits.count <= 1 {
                print("   🚨 LOGITS COLLAPSED - All values are \(logitsForPosition.first ?? 0)")
                print("   This indicates quantization issues or model corruption")
            }
            
            // Find top tokens
            let topTokens = logitsForPosition.enumerated()
                .sorted { $0.1 > $1.1 }
                .prefix(5)
            
            print("   Top 5 tokens:")
            for (index, (tokenId, logit)) in topTokens.enumerated() {
                print("     \(index + 1). Token \(tokenId): \(logit)")
            }
            
            // Check for suspicious patterns
            let allSame = logitsForPosition.allSatisfy { $0 == logitsForPosition[0] }
            if allSame {
                print("   🚨 ALL LOGITS ARE IDENTICAL - Model is not generating properly")
            }
            
            let allZero = logitsForPosition.allSatisfy { $0 == 0 }
            if allZero {
                print("   🚨 ALL LOGITS ARE ZERO - Model output is corrupted")
            }
        }
        
        print("🔍 === END LOGITS ANALYSIS ===")
    }
    
    // MARK: - Token Generation Debug
    static func debugTokenGeneration(_ tokenIds: [Int], vocabSize: Int) {
        print("🔍 === TOKEN GENERATION DEBUG ===")
        
        print("📝 Generated \(tokenIds.count) tokens")
        print("📊 Token IDs: \(tokenIds.prefix(20))...")
        
        // Check for invalid token IDs
        let invalidTokens = tokenIds.filter { $0 < 0 || $0 >= vocabSize }
        if !invalidTokens.isEmpty {
            print("❌ Invalid token IDs found: \(invalidTokens)")
        }
        
        // Check for repetitive tokens
        var repetitionCount = 0
        for i in 1..<tokenIds.count {
            if tokenIds[i] == tokenIds[i-1] {
                repetitionCount += 1
            }
        }
        
        if repetitionCount > 0 {
            print("⚠️ Repetitive tokens detected: \(repetitionCount) repetitions")
        }
        
        // Check for special token patterns
        let specialTokenIds = [0, 1, 2, 50265, 50266, 50267, 50268] // BOS, PAD, EOS, special tokens
        let specialTokenCount = tokenIds.filter { specialTokenIds.contains($0) }.count
        print("🎯 Special tokens found: \(specialTokenCount)")
        
        // Check for single character output indicators
        if tokenIds.count == 1 {
            print("🚨 SINGLE TOKEN GENERATED - This will result in single character output")
        }
        
        if tokenIds.count <= 3 {
            print("⚠️ Very few tokens generated - may indicate model issues")
        }
        
        print("🔍 === END TOKEN GENERATION DEBUG ===")
    }
    
    // MARK: - Quantization Detection
    static func detectQuantizationIssues(_ model: MLModel) {
        print("🔍 === QUANTIZATION ANALYSIS ===")
        
        let description = model.modelDescription
        
        // Check if model is quantized
        var hasQuantizedLayers = false
        
        // Look for quantization indicators in model description
        let metadata = description.metadata
        print("📋 Model metadata:")
        for (key, value) in metadata {
            print("  \(key): \(value)")
            
            // Check for quantization indicators in metadata values
            if let stringValue = value as? String {
                if stringValue.contains("quantization") || stringValue.contains("int8") || stringValue.contains("int16") {
                    hasQuantizedLayers = true
                }
            }
        }
        
        // Check input/output data types for quantization indicators
        for (name, feature) in description.inputDescriptionsByName {
            if let constraint = feature.multiArrayConstraint {
                // Check for supported data types
                switch constraint.dataType {
                case .int32:
                    // int32 is fine, not quantized
                    break
                case .float32, .double:
                    // float types are fine
                    break
                default:
                    // Any other type might indicate quantization
                    print("⚠️ Potentially quantized input detected: \(name) uses \(constraint.dataType)")
                    hasQuantizedLayers = true
                }
            }
        }
        
        for (name, feature) in description.outputDescriptionsByName {
            if let constraint = feature.multiArrayConstraint {
                // Check for supported data types
                switch constraint.dataType {
                case .int32:
                    // int32 is fine, not quantized
                    break
                case .float32, .double:
                    // float types are fine
                    break
                default:
                    // Any other type might indicate quantization
                    print("⚠️ Potentially quantized output detected: \(name) uses \(constraint.dataType)")
                    hasQuantizedLayers = true
                }
            }
        }
        
        if hasQuantizedLayers {
            print("🚨 QUANTIZED MODEL DETECTED")
            print("   Quantization can cause logits collapse and single character output")
            print("   Consider using float16 or float32 precision instead")
        } else {
            print("✅ No quantization detected")
        }
        
        print("🔍 === END QUANTIZATION ANALYSIS ===")
    }
    
    // MARK: - Comprehensive Model Health Check
    static func performModelHealthCheck(_ model: MLModel, name: String = "Model") -> Bool {
        print("🏥 === MODEL HEALTH CHECK: \(name) ===")
        
        var issuesFound = 0
        
        // 1. Inspect model structure
        inspectModel(model, name: name)
        
        // 2. Check for quantization issues
        detectQuantizationIssues(model)
        
        // 3. Validate input/output constraints
        let description = model.modelDescription
        
        for (inputName, inputFeature) in description.inputDescriptionsByName {
            if let constraint = inputFeature.multiArrayConstraint {
                print("🔍 Checking input: \(inputName)")
                
                // Check for problematic data types
                switch constraint.dataType {
                case .int32, .float32, .double:
                    // These are supported types
                    break
                default:
                    print("   ⚠️ Potentially problematic data type: \(constraint.dataType)")
                    issuesFound += 1
                }
                
                // Check for shape issues
                if constraint.shape.count == 0 {
                    print("   ❌ Invalid shape for input")
                    issuesFound += 1
                }
            }
        }
        
        for (outputName, outputFeature) in description.outputDescriptionsByName {
            if let constraint = outputFeature.multiArrayConstraint {
                print("🔍 Checking output: \(outputName)")
                
                // Check for problematic data types
                switch constraint.dataType {
                case .int32, .float32, .double:
                    // These are supported types
                    break
                default:
                    print("   ⚠️ Potentially problematic data type: \(constraint.dataType)")
                    issuesFound += 1
                }
            }
        }
        
        // Summary
        print("📊 Health Check Summary:")
        if issuesFound == 0 {
            print("   ✅ Model appears healthy")
        } else {
            print("   ⚠️ Found \(issuesFound) potential issues")
        }
        
        print("🏥 === END MODEL HEALTH CHECK ===")
        return issuesFound == 0
    }
}

// MARK: - Tokenizer Debug Utilities
class TokenizerDebugger {
    
    static func validateTokenizer(_ tokenizer: BARTTokenizerSemantic) -> Bool {
        print("🔍 === TOKENIZER VALIDATION ===")
        
        var issuesFound = 0
        
        // Check if tokenizer is loaded
        if !tokenizer.isLoaded {
            print("❌ Tokenizer not fully loaded")
            issuesFound += 1
        }
        
        // Check if semantic features are ready
        if !tokenizer.isSemanticReady {
            print("❌ Semantic features not ready")
            issuesFound += 1
        }
        
        // Test basic tokenization
        let testText = "Hello world"
        do {
            let (inputIds, attentionMask) = try tokenizer.encode(testText, maxLength: 10)
            print("✅ Basic tokenization test passed")
            print("   Input: '\(testText)'")
            print("   Token IDs: \(inputIds)")
            print("   Attention mask: \(attentionMask)")
            
            // Check for reasonable token IDs
            let invalidIds = inputIds.filter { $0 < 0 }
            if !invalidIds.isEmpty {
                print("   ⚠️ Negative token IDs found: \(invalidIds)")
                issuesFound += 1
            }
            
        } catch {
            print("❌ Basic tokenization test failed: \(error)")
            issuesFound += 1
        }
        
        // Test special tokens
        let specialTokens = ["<s>", "</s>", "[START_COMMENTARY]", "[END_COMMENTARY]"]
        for token in specialTokens {
            if let tokenId = tokenizer.getSpecialTokenId(for: token) {
                print("✅ Special token '\(token)' found with ID: \(tokenId)")
                
                // Check for zero IDs (indicates tokenizer issue)
                if tokenId == 0 {
                    print("   ⚠️ Special token has ID 0 - this may cause issues")
                    issuesFound += 1
                }
            } else {
                print("❌ Special token '\(token)' not found")
                issuesFound += 1
            }
        }
        
        // Summary
        print("📊 Tokenizer Validation Summary:")
        if issuesFound == 0 {
            print("   ✅ Tokenizer appears healthy")
        } else {
            print("   ⚠️ Found \(issuesFound) issues")
        }
        
        print("🔍 === END TOKENIZER VALIDATION ===")
        return issuesFound == 0
    }
}
