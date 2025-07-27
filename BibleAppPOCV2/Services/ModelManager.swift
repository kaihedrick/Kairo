import Foundation
import CoreML

/// Service for managing Bible summarizer models
class ModelManager: ObservableObject {
    @Published var availableModels: [String] = []
    @Published var currentModel: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    init() {
        scanForModels()
    }
    
    /// Scan for available models in bundle and documents
    func scanForModels() {
        availableModels.removeAll()
        
        // Scan bundle for models
        scanBundleForModels()
        
        // Scan documents directory for models
        scanDocumentsForModels()
        
        print("📊 Found \(availableModels.count) available models: \(availableModels.joined(separator: ", "))")
    }
    
    private func scanBundleForModels() {
        let possibleModelNames = [
            "BibleSummarizer_improved_full",
            "BibleSummarizer_full",
            "BibleSummarizer",
            "BART_Bible_Summarizer",
            "Bible_BART_Model"
        ]
        
        for modelName in possibleModelNames {
            let locations = [
                (modelName, "mlpackage", "Resources/ML"),
                (modelName, "mlpackage", nil),
                (modelName, "mlmodelc", nil),
                (modelName, "mlmodel", nil)
            ]
            
            for (name, ext, subdir) in locations {
                if Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdir) != nil {
                    let fullName = "\(name).\(ext)"
                    if !availableModels.contains(fullName) {
                        availableModels.append(fullName)
                    }
                    break
                }
            }
        }
        
        // Also scan all bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            do {
                let files = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                for file in files {
                    if (file.contains("BibleSummarizer") || file.contains("BART") || file.contains("Bible")) && 
                       (file.hasSuffix(".mlpackage") || file.hasSuffix(".mlmodelc") || file.hasSuffix(".mlmodel")) {
                        if !availableModels.contains(file) {
                            availableModels.append(file)
                        }
                    }
                }
            } catch {
                print("❌ Error scanning bundle resources: \(error)")
            }
        }
    }
    
    private func scanDocumentsForModels() {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: documentsPath.path)
            for file in files {
                if (file.contains("BibleSummarizer") || file.contains("BART") || file.contains("Bible")) && 
                   (file.hasSuffix(".mlpackage") || file.hasSuffix(".mlmodelc") || file.hasSuffix(".mlmodel")) {
                    if !availableModels.contains(file) {
                        availableModels.append(file)
                    }
                }
            }
        } catch {
            print("❌ Error scanning documents directory: \(error)")
        }
    }
    
    /// Get the best available model (prioritizes improved version)
    func getBestModel() -> String? {
        let priorityOrder = [
            "BibleSummarizer_improved_full",
            "BibleSummarizer_full",
            "BibleSummarizer"
        ]
        
        for priorityName in priorityOrder {
            for model in availableModels {
                if model.contains(priorityName) {
                    return model
                }
            }
        }
        
        return availableModels.first
    }
    
    /// Download a model from a URL (placeholder for future implementation)
    func downloadModel(from url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        isLoading = true
        errorMessage = nil
        
        // This is a placeholder - you would implement actual download logic here
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isLoading = false
            completion(.failure(NSError(domain: "ModelManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download not implemented yet"])))
        }
    }
    
    /// Compile a model if needed
    func compileModelIfNeeded(modelName: String) throws -> URL {
        // Find the source model
        var sourceURL: URL?
        
        // Check bundle first
        let locations = [
            (modelName, "mlpackage", "Resources/ML"),
            (modelName, "mlpackage", nil),
            (modelName, "mlmodelc", nil),
            (modelName, "mlmodel", nil)
        ]
        
        for (name, ext, subdir) in locations {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdir) {
                sourceURL = url
                break
            }
        }
        
        // Check documents directory
        if sourceURL == nil {
            let docURL = documentsPath.appendingPathComponent(modelName)
            if FileManager.default.fileExists(atPath: docURL.path) {
                sourceURL = docURL
            }
        }
        
        guard let url = sourceURL else {
            throw NSError(domain: "ModelManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model not found: \(modelName)"])
        }
        
        // If it's already compiled, return it
        if url.pathExtension == "mlmodelc" {
            return url
        }
        
        // Compile the model
        let compiledURL = documentsPath.appendingPathComponent("\(modelName).mlmodelc")
        
        if FileManager.default.fileExists(atPath: compiledURL.path) {
            print("✅ Found existing compiled model: \(modelName)")
            return compiledURL
        }
        
        print("🔧 Compiling model: \(modelName)...")
        let compiledModelURL = try MLModel.compileModel(at: url)
        
        // Copy to documents directory for future use
        try FileManager.default.copyItem(at: compiledModelURL, to: compiledURL)
        print("✅ Model compiled and saved to: \(compiledURL.path)")
        
        return compiledURL
    }
    
    /// Get model information
    func getModelInfo(modelName: String) -> [String: Any]? {
        var modelURL: URL?
        
        // Try to find the model
        let locations = [
            (modelName, "mlpackage", "Resources/ML"),
            (modelName, "mlpackage", nil),
            (modelName, "mlmodelc", nil),
            (modelName, "mlmodel", nil)
        ]
        
        for (name, ext, subdir) in locations {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdir) {
                modelURL = url
                break
            }
        }
        
        if modelURL == nil {
            let docURL = documentsPath.appendingPathComponent(modelName)
            if FileManager.default.fileExists(atPath: docURL.path) {
                modelURL = docURL
            }
        }
        
        guard let url = modelURL else { return nil }
        
        do {
            let model = try MLModel(contentsOf: url)
            let description = model.modelDescription
            
            return [
                "name": modelName,
                "path": url.path,
                "inputFeatures": Array(description.inputDescriptionsByName.keys),
                "outputFeatures": Array(description.outputDescriptionsByName.keys),
                "metadata": description.metadata
            ]
        } catch {
            print("❌ Error getting model info: \(error)")
            return nil
        }
    }
} 