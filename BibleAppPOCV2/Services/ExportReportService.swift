// filepath: BibleAppPOCV2/Services/ExportReportService.swift
import Foundation

/// Loads special token IDs from export_report.json to drive formatting and splitting.
/// Use the exported IDs to ensure the model sees the same structure it was trained on.
struct ExportReport: Decodable {
    struct ModelIO: Decodable { 
        let seq_len: Int, n_layer: Int, n_head: Int, head_dim: Int, use_cache: Bool 
    }
    let vocab_size: Int
    let model_io: ModelIO
    let special_token_ids: [String: Int]
}

enum Special: String, CaseIterable {
    case START_COMMENTARY = "START_COMMENTARY"
    case END_COMMENTARY = "END_COMMENTARY"
    case START_DEVOTIONAL = "START_DEVOTIONAL"
    case END_DEVOTIONAL = "END_DEVOTIONAL"
    case PAD = "PAD"
    case VERSE = "VERSE"
    case VERSE_REF = "VERSE_REF"
    case VERSE_TEXT = "VERSE_TEXT"
    case VERSE_ID = "VERSE_ID"
}

final class ExportReportService {
    static let shared = ExportReportService()
    let report: ExportReport?
    
    private init() {
        // Try to load from the ML directory first, then fall back to main bundle
        let url: URL?
        if let mlUrl = Bundle.main.url(forResource: "export_report", withExtension: "json", subdirectory: "ML/Models") {
            url = mlUrl
        } else if let mainUrl = Bundle.main.url(forResource: "export_report", withExtension: "json") {
            url = mainUrl
        } else {
            url = nil
        }
        
        if let url = url {
            do {
                let data = try Data(contentsOf: url)
                self.report = try JSONDecoder().decode(ExportReport.self, from: data)
                print("✅ Loaded export report with \(report?.special_token_ids.count ?? 0) special tokens")
            } catch {
                print("❌ Error loading export report: \(error), using fallback")
                self.report = ExportReportService.createFallbackReport()
            }
        } else {
            print("⚠️ Warning: Could not find export_report.json, using fallback")
            self.report = ExportReportService.createFallbackReport()
        }
    }
    
    private static func createFallbackReport() -> ExportReport {
        // Create a fallback report with reasonable defaults for testing
        let fallbackIO = ExportReport.ModelIO(
            seq_len: 512,
            n_layer: 12,
            n_head: 12,
            head_dim: 64,
            use_cache: true
        )
        
        let fallbackSpecialTokens: [String: Int] = [
            "START_COMMENTARY": 1000,
            "END_COMMENTARY": 1001,
            "START_DEVOTIONAL": 1002,
            "END_DEVOTIONAL": 1003,
            "PAD": 0,
            "VERSE": 1004,
            "VERSE_REF": 1005,
            "VERSE_TEXT": 1006,
            "VERSE_ID": 1007
        ]
        
        return ExportReport(
            vocab_size: 50257, // Standard GPT-2 vocabulary size
            model_io: fallbackIO,
            special_token_ids: fallbackSpecialTokens
        )
    }
    
    /// Get special token ID for a given special token type
    func id(for special: Special) -> Int? { 
        return report?.special_token_ids[special.rawValue] 
    }
    
    /// Get all special token IDs
    var specialTokenIDs: [String: Int] {
        return report?.special_token_ids ?? [:]
    }
}
