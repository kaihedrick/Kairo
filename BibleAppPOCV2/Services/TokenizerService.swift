import Foundation

class TokenizerService {
    static let shared = TokenizerService()
    
    // Special tokens
    private let specialTokens = [
        "start_commentary": "[START_COMMENTARY]",
        "end_commentary": "[END_COMMENTARY]",
        "start_devotional": "[START_DEVOTIONAL]",
        "end_devotional": "[END_DEVOTIONAL]",
        "verse_separator": "[VERSE]",
        "verse_reference": "[VERSE_REF]",
        "verse_text": "[VERSE_TEXT]",
        "verse_id": "[VERSE_ID]",
        "pad_token": "[PAD]"
    ]
    
    func tokenize(_ text: String) -> [Int] {
        // Simple tokenization - in production, use a proper tokenizer
        // This is a placeholder implementation
        return text.components(separatedBy: " ").map { $0.hashValue % 50266 }
    }
    
    func detokenize(_ tokens: [Int]) -> String {
        // Simple detokenization - in production, use a proper tokenizer
        return tokens.map { String($0) }.joined(separator: " ")
    }
    
    func formatInput(verseRef: String, verseText: String) -> String {
        let verseId = verseRef
            .uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")  // colon → underscore to match training
            .replacingOccurrences(of: "-", with: "_")   // if any
            .replacingOccurrences(of: "[^A-Z0-9_]+", with: "", options: .regularExpression)
        return """
        [VERSE_ID] \(verseId)
        [VERSE_REF] \(verseRef)
        [VERSE_TEXT] \(verseText)
        [VERSE]
        [START_COMMENTARY]
        """
    }
}
