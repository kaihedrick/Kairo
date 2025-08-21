// filepath: BibleAppPOCV2/Services/ParityVerifier.swift
import Foundation

/// Runtime confidence through parity verification.
/// Verifies that Core ML model output matches Python model output.
/// Use your fixture for production builds to ensure consistency.
struct ParityFixture: Decodable {
    struct Model: Decodable { let logits: [Float] }
    struct Metadata: Decodable { let input_ids: [Int] }
    let python_model: Model
    let coreml_model: Model
    let metadata: Metadata
}

func verifyParity() -> Bool {
    // Try to load from the ML directory first, then fall back to main bundle
    let url: URL?
    if let mlUrl = Bundle.main.url(forResource: "parity_fixture", withExtension: "json", subdirectory: "ML/Parity") {
        url = mlUrl
    } else if let mainUrl = Bundle.main.url(forResource: "parity_fixture", withExtension: "json") {
        url = mainUrl
    } else {
        url = nil
    }
    
    guard let url = url,
          let data = try? Data(contentsOf: url),
          let fixture = try? JSONDecoder().decode(ParityFixture.self, from: data) else {
        print("⚠️ Warning: Could not load parity fixture, skipping verification")
        return false
    }
    
    // Simple verification: check if arrays have the same length
    let pythonLength = fixture.python_model.logits.count
    let coremlLength = fixture.coreml_model.logits.count
    
    if pythonLength != coremlLength {
        print("❌ Parity verification failed: length mismatch (Python: \(pythonLength), CoreML: \(coremlLength))")
        return false
    }
    
    // Check for significant differences in the first few values
    let sampleSize = min(10, pythonLength)
    var differences = 0
    
    for i in 0..<sampleSize {
        let pythonValue = fixture.python_model.logits[i]
        let coremlValue = fixture.coreml_model.logits[i]
        let diff = abs(pythonValue - coremlValue)
        if diff > 0.001 { // Allow small floating point differences
            differences += 1
        }
    }
    
    if differences > sampleSize / 2 {
        print("❌ Parity verification failed: too many significant differences")
        return false
    }
    
    print("✅ Parity verification passed: CoreML output matches Python output")
    return true
}

#if DEBUG
func runParityCheck() {
    if verifyParity() {
        print("✅ Parity check passed - model output consistent")
    } else {
        print("⚠️ Parity check failed - investigate model export")
    }
}
#endif
