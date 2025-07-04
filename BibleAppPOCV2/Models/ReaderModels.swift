// ReaderModels.swift
// Shared models for Bible reader views and generators.

import Foundation
import SwiftUI

/// Identifies a single verse in the Bible.
struct VerseKey: Hashable, Codable {
    let book: String
    let chapter: Int
    let verse: Int

    var description: String { "\(book) \(chapter):\(verse)" }
}

/// Additional context about where a page sits in a book.
struct PageNavigationContext: Equatable {
    let isFirstVerseOfBook: Bool
    let isLastVerseOfBook: Bool
}

/// Represents a chunk of text from a specific verse.
struct PageSegment: Identifiable {
    let id = UUID()
    let attributed: AttributedString
    let verseKey: VerseKey
}

/// A lightweight representation of visible Bible text.
struct OptimizedPageSlice: Identifiable, Equatable {
    let id = UUID()
    let content: AttributedString
    let verseKeys: [VerseKey]
    let startVerse: VerseKey
    let endVerse: VerseKey
    let navigationContext: PageNavigationContext

    static func == (lhs: OptimizedPageSlice, rhs: OptimizedPageSlice) -> Bool {
        lhs.id == rhs.id &&
        lhs.startVerse == rhs.startVerse &&
        lhs.endVerse == rhs.endVerse &&
        lhs.verseKeys.count == rhs.verseKeys.count
    }
}

/// Raw generated data before being converted for display.
struct GeneratedPage {
    let segments: [PageSegment]
    let startKey: VerseKey
    let navigationContext: PageNavigationContext
}
