import Foundation

struct VerseSummary: Identifiable, Codable, Equatable {
    let id: UUID
    let reference: String            // E.g. "John 3:16"
    let book: String                 // E.g. "John"
    let chapter: Int                 // E.g. 3
    let verse: Int                  // E.g. 16
    let summaryText: String          // Output from Apple AI
    let generatedAt: Date            // Timestamp for when the summary was generated
    let modelVersion: String?        // Optional (e.g. "foundation-small")
    let promptTemplate: String?      // Optional (to help debug or evolve prompt design)

    init(reference: String, book: String, chapter: Int, verse: Int, summaryText: String, modelVersion: String? = nil, promptTemplate: String? = nil) {
        self.id = UUID()
        self.reference = reference
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.summaryText = summaryText
        self.generatedAt = Date()
        self.modelVersion = modelVersion
        self.promptTemplate = promptTemplate
    }
}
