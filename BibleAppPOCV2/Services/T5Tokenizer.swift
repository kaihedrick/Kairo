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
        guard let url = Bundle.main.url(forResource: "tokenizer", withExtension: "json", subdirectory: "Resources/ML") else { 
            print("❌ Could not find tokenizer.json in Resources/ML")
            return 
        }
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            print("🔍 Tokenizer.json structure: \(json?.keys.sorted() ?? [])")
            
            // Try different possible vocabulary structures
            if let model = json?["model"] as? [String: Any],
               let vocabDict = model["vocab"] as? [String: Int] {
                vocab = vocabDict
                print("✅ Loaded vocabulary from model.vocab with \(vocab.count) tokens")
            } else if let vocabDict = json?["vocab"] as? [String: Int] {
                vocab = vocabDict
                print("✅ Loaded vocabulary from root vocab with \(vocab.count) tokens")
            } else if let addedTokens = json?["added_tokens"] as? [String: Any] {
                // Handle added_tokens format
                var tempVocab: [String: Int] = [:]
                for (key, value) in addedTokens {
                    if let tokenInfo = value as? [String: Any],
                       let id = tokenInfo["id"] as? Int {
                        tempVocab[key] = id
                    }
                }
                vocab = tempVocab
                print("✅ Loaded vocabulary from added_tokens with \(vocab.count) tokens")
            } else {
                print("❌ Could not find vocabulary in expected format")
                print("🔍 Available top-level keys: \(json?.keys.sorted() ?? [])")
                
                // Create a basic vocabulary as fallback
                vocab = [
                    "<pad>": 0,
                    "</s>": 1,
                    "<unk>": 2,
                    "the": 3,
                    "and": 4,
                    "of": 5,
                    "to": 6,
                    "in": 7,
                    "a": 8,
                    "is": 9,
                    "that": 10
                ]
                print("⚠️ Using fallback vocabulary with \(vocab.count) tokens")
            }
            
            // Print some sample vocabulary entries
            let sampleEntries = Array(vocab.prefix(10))
            print("🔍 Sample vocabulary entries: \(sampleEntries)")
            
        } catch {
            print("❌ Failed to load vocab: \(error)")
            
            // Create a basic vocabulary as fallback
            vocab = [
                "<pad>": 0,
                "</s>": 1,
                "<unk>": 2,
                "the": 3,
                "and": 4,
                "of": 5,
                "to": 6,
                "in": 7,
                "a": 8,
                "is": 9,
                "that": 10
            ]
            print("⚠️ Using fallback vocabulary due to error")
        }
    }

    // Enhanced tokenization with better error handling and debugging
    func tokenize(_ verse: String) -> [Int] {
        print("🔤 Tokenizing verse: '\(verse.prefix(50))...'")
        
        // Handle empty or whitespace-only input
        let trimmedVerse = verse.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedVerse.isEmpty {
            print("⚠️ Empty verse input, returning default token")
            return [0] // Return PAD token for empty input
        }
        
        // Basic whitespace tokenization
        let tokens = trimmedVerse.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        print("🔤 Split into \(tokens.count) word tokens")
        
        // Convert to token IDs with fallback
        var tokenIds: [Int] = []
        let unkTokenId = vocab["<unk>"] ?? 2 // Default UNK token ID
        
        for token in tokens {
            if let tokenId = vocab[token] {
                tokenIds.append(tokenId)
            } else {
                print("⚠️ Unknown token '\(token)', using UNK token")
                tokenIds.append(unkTokenId)
            }
        }
        
        print("🔤 Converted to \(tokenIds.count) token IDs: \(tokenIds.prefix(10))")
        
        // Ensure we have at least one token
        if tokenIds.isEmpty {
            print("⚠️ No valid tokens found, using default token")
            return [0] // Return PAD token
        }
        
        return tokenIds
    }
}
