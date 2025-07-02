
//
//  VerseEntry.swift
//  AIStudyBiblePOC
//
//  Created by Jeff Hedrick on 6/10/25.
//

import Foundation

struct VerseEntry: Codable, Identifiable, Equatable {  // ✅ Add Equatable here
    let id = UUID()
    let book: String
    let chapter: Int
    let verse: Int
    let text: String

    enum CodingKeys: String, CodingKey {
        case book, chapter, verse, text
    }

    // ✅ Explicit Equatable implementation (optional, but safer)
    static func == (lhs: VerseEntry, rhs: VerseEntry) -> Bool {
        return lhs.book == rhs.book &&
               lhs.chapter == rhs.chapter &&
               lhs.verse == rhs.verse
    }
}
