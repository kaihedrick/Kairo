// filepath: BibleAppPOCV2/Services/Generator.swift
import CoreML

/// Single-token step generation with KV cache management.
/// Uses bool attention mask to avoid exporter-unfriendly dtype ops.
/// Keeps KV cache in memory for efficient generation.
struct KV {
    var k: [MLMultiArray] // present_k_0..L-1
    var v: [MLMultiArray] // present_v_0..L-1
}

final class Generator {
    private let ml: MLModel?
    private let nLayer: Int
    private let nHead: Int
    private let headDim: Int
    
    init() {
        let model = CommentaryModel.shared
        self.ml = model.model
        self.nLayer = model.nLayer
        self.nHead = model.nHead
        self.headDim = model.headDim
    }
    
    func createEmptyCaches() -> KV {
        let k = (0..<nLayer).map { _ in 
            try! MLMultiArray(
                shape: [1, NSNumber(value: nHead), NSNumber(value: 0), NSNumber(value: headDim)],
                dataType: .float32
            )
        }
        let v = (0..<nLayer).map { _ in 
            try! MLMultiArray(
                shape: [1, NSNumber(value: nHead), NSNumber(value: 0), NSNumber(value: headDim)],
                dataType: .float32
            )
        }
        return KV(k: k, v: v)
    }
    
    /// Generate a single token step
    func step(promptIds: [Int], kv: inout KV) throws -> Int {
        guard let ml = ml else {
            print("❌ Error: Core ML model not available")
            throw NSError(domain: "Generator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Core ML model not available"])
        }
        
        // Prepare inputs
        var inputs: [String: Any] = [:]
        
        // Create input_ids MLMultiArray
        let inputIds = try MLMultiArray(shape: [NSNumber(value: promptIds.count)], dataType: .int32)
        for (i, tokenId) in promptIds.enumerated() {
            inputIds[i] = NSNumber(value: tokenId)
        }
        inputs["input_ids"] = inputIds
        
        // Create attention_mask MLMultiArray
        let attentionMask = try MLMultiArray(shape: [NSNumber(value: promptIds.count)], dataType: .int32)
        for i in 0..<promptIds.count {
            attentionMask[i] = NSNumber(value: 1)
        }
        inputs["attention_mask"] = attentionMask
        
        inputs["use_cache"] = NSNumber(value: true)
        
        // Add KV cache if available
        for i in 0..<nLayer {
            inputs["present_k_\(i)"] = kv.k[i]
            inputs["present_v_\(i)"] = kv.v[i]
        }
        
        // Run prediction
        let out = try ml.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
        
        // Extract logits and get next token
        let logits = out.featureValue(for: "logits")?.multiArrayValue
        let nextToken = getNextToken(from: logits)
        
        // Update KV cache
        updateKVCache(kv: &kv, output: out)
        
        return nextToken
    }
    
    private func getNextToken(from logits: MLMultiArray?) -> Int {
        // Simple greedy decoding - get the token with highest probability
        guard let logits = logits else { return 0 }
        
        var maxProb: Float = -Float.infinity
        var maxToken = 0
        
        for i in 0..<logits.count {
            let prob = logits[i].floatValue
            if prob > maxProb {
                maxProb = prob
                maxToken = i
            }
        }
        
        return maxToken
    }
    
    private func updateKVCache(kv: inout KV, output: MLFeatureProvider) {
        // Update KV cache with new key and value arrays
        for i in 0..<nLayer {
            if let newK = output.featureValue(for: "present_k_\(i)")?.multiArrayValue {
                kv.k[i] = newK
            }
            if let newV = output.featureValue(for: "present_v_\(i)")?.multiArrayValue {
                kv.v[i] = newV
            }
        }
    }
    
    /// Check if the generator is ready to use
    var isReady: Bool {
        return ml != nil
    }
}
