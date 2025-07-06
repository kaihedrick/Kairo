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
    let isSplit: Bool

    init(attributed: AttributedString, verseKey: VerseKey, isSplit: Bool = false) {
        self.attributed = attributed
        self.verseKey = verseKey
        self.isSplit = isSplit
    }
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
    /// The first verse actually visible on the rendered page
    let startVisibleVerse: VerseKey
    /// The last verse visible on the rendered page
    let endVisibleVerse: VerseKey
}

extension GeneratedPage {
    func toOptimizedPageSlice() -> OptimizedPageSlice {
        let content = segments.reduce(into: AttributedString()) { result, seg in
            result += seg.attributed
        }
        let verseKeys = segments.map { $0.verseKey }
        // Use the provided visible range if available, otherwise fall back to the first/last keys
        let startVerse = startVisibleVerse
        let endVerse = endVisibleVerse
        return OptimizedPageSlice(
            content: content,
            verseKeys: verseKeys,
            startVerse: startVerse,
            endVerse: endVerse,
            navigationContext: navigationContext
        )
    }
}

extension OptimizedPageSlice {
    /// Canonical text for the navigation bar derived from the page's verse range.
    var navTitle: String {
        let start = startVerse
        let end = endVerse
        let abbrev = start.book.prefix(3)
        if start.chapter == end.chapter {
            return "\(abbrev) \(start.chapter):\(start.verse)-\(end.verse)"
        } else {
            return "\(abbrev) \(start.chapter):\(start.verse)–\(end.chapter):\(end.verse)"
        }
    }
}
