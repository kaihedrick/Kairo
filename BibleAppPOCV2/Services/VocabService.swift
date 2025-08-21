// filepath: BibleAppPOCV2/Services/VocabService.swift
import Foundation

/// Single source of truth for token decoding from clean exported data.
/// Decodes from token IDs using id_to_token.json (UTF-8 clean, no mojibake).
/// Do not re-encode/"fix" strings - trust the clean exported data.
final class VocabService {
    static let shared = VocabService()
    private let map: [Int: String]
    
    private init() {
        // Try to load from the ML directory first, then fall back to main bundle
        let url: URL
        if let mlUrl = Bundle.main.url(forResource: "id_to_token", withExtension: "json", subdirectory: "ML/Models") {
            url = mlUrl
        } else if let mainUrl = Bundle.main.url(forResource: "id_to_token", withExtension: "json") {
            url = mainUrl
        } else {
            // Fallback: create a minimal vocabulary for testing
            print("⚠️ Warning: Could not load id_to_token.json, using fallback vocabulary")
            self.map = [0: "[UNK]", 1: "test", 2: "token"]
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            // file is UTF-8; decode as such
            let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            var temp = [Int: String]()
            temp.reserveCapacity(raw.count)
            for (k, v) in raw {
                if let id = Int(k), let tok = v as? String { 
                    temp[id] = tok 
                }
            }
            self.map = temp
            print("✅ Loaded vocabulary with \(temp.count) tokens")
        } catch {
            print("❌ Error loading vocabulary: \(error)")
            // Fallback: create a minimal vocabulary for testing
            self.map = [0: "[UNK]", 1: "test", 2: "token"]
        }
    }
    
        func token(for id: Int) -> String {
        map[id] ?? "[UNK]"
    }

    /// Check if the vocab service is ready
    var isReady: Bool {
        return !map.isEmpty
    }
}

// MARK: - Array Extension for Token Decoding

extension Array where Element == Int {
    /// Join tokens → text (no sanitizer needed)
    func decodeToString() -> String {
        let vocab = VocabService.shared
        // naive join; post-formatters (e.g. spaces) can be applied outside
        return self.map { vocab.token(for: $0) }.joined()
    }
}
