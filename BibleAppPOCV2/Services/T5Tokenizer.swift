// File: BibleAppPOCV2/Services/T5Tokenizer.swift
// Directory: Services
// Purpose: Tokenize verse input for ML pipeline integration

import Foundation

class T5Tokenizer {
    // Loads vocabulary from tokenizer.json
    var vocab: [String: Int] = [:] // Made internal for detokenization

    init() {
        loadVocab()
    }

    private func loadVocab() {
        guard let url = Bundle.main.url(forResource: "tokenizer", withExtension: "json", subdirectory: "Resources/ML") else { return }
        do {
            let data = try Data(contentsOf: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let model = json["model"] as? [String: Any],
               let vocabDict = model["vocab"] as? [String: Int] {
                vocab = vocabDict
            }
        } catch {
            print("Failed to load vocab: \(error)")
        }
    }

    // Basic whitespace tokenization and vocab lookup
    func tokenize(_ verse: String) -> [Int] {
        let tokens = verse.components(separatedBy: .whitespacesAndNewlines)
        return tokens.compactMap { vocab[$0] ?? vocab["<unk>"] }
    }
}
