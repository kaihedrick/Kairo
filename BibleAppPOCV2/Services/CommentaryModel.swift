// filepath: BibleAppPOCV2/Services/CommentaryModel.swift
import CoreML

/// Clean Core ML model loading with configuration from export report.
/// Loads the model and provides access to model architecture details.
final class CommentaryModel {
    static let shared = CommentaryModel()
    var model: MLModel?
    var nLayer: Int, nHead: Int, headDim: Int
    
    private init() {
        // Try to load from the ML directory first, then fall back to main bundle
        let url: URL?
        if let mlUrl = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage", subdirectory: "ML/Models") {
            url = mlUrl
        } else if let mainUrl = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlpackage") {
            url = mainUrl
        } else {
            url = nil
        }
        
        if let url = url {
            do {
                self.model = try MLModel(contentsOf: url)
            } catch {
                print("❌ Error loading Core ML model: \(error)")
                self.model = nil
            }
        } else {
            self.model = nil
        }
        
        // Derive dimensions from report (or default to 0)
        let io = ExportReportService.shared.report?.model_io
        nLayer = io?.n_layer ?? 0
        nHead = io?.n_head ?? 0
        headDim = io?.head_dim ?? 0
        
        if model != nil {
            print("✅ Loaded Core ML model with \(nLayer) layers, \(nHead) heads, \(headDim) head dimension")
        } else {
            print("⚠️ Warning: Core ML model not available, using fallback dimensions")
        }
    }
    
    /// Get model configuration for KV cache management
    var modelConfig: (nLayer: Int, nHead: Int, headDim: Int) {
        return (nLayer: nLayer, nHead: nHead, headDim: headDim)
    }
    
    /// Check if the model is available
    var isModelAvailable: Bool {
        return model != nil
    }
}
