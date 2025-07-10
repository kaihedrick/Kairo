import Foundation

struct VerseKey: Hashable, Codable {
    let book: String
    let chapter: Int
    let verse: Int

    var description: String { "\(book) \(chapter):\(verse)" }
}
