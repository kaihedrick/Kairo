// filepath: BibleAppPOCV2/Models/ReaderModels.swift
// ReaderModels.swift
// Shared models for Bible reader views and generators.

import Foundation
import SwiftUI

/// Identifies a single verse in the Bible.
public struct VerseKey: Hashable, Codable {
    let book: String
    let chapter: Int
    let verse: Int

    var description: String { "\(book) \(chapter):\(verse)" }
}

/// Additional context about where a page sits in a book.
struct PageNavigationContext: Equatable, Codable {
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
struct OptimizedPageSlice: Identifiable, Equatable, Codable {
    let id: UUID
    let content: AttributedString
    let verseKeys: [VerseKey]
    let startVerse: VerseKey
    let endVerse: VerseKey
    let navigationContext: PageNavigationContext
    
    // Custom Codable implementation to handle AttributedString
    enum CodingKeys: String, CodingKey {
        case id, verseKeys, startVerse, endVerse, navigationContext, contentString
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(verseKeys, forKey: .verseKeys)
        try container.encode(startVerse, forKey: .startVerse)
        try container.encode(endVerse, forKey: .endVerse)
        try container.encode(navigationContext, forKey: .navigationContext)
        try container.encode(String(content.characters), forKey: .contentString)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        verseKeys = try container.decode([VerseKey].self, forKey: .verseKeys)
        startVerse = try container.decode(VerseKey.self, forKey: .startVerse)
        endVerse = try container.decode(VerseKey.self, forKey: .endVerse)
        navigationContext = try container.decode(PageNavigationContext.self, forKey: .navigationContext)
        let contentString = try container.decode(String.self, forKey: .contentString)
        content = AttributedString(contentString)
    }
    
    init(content: AttributedString, verseKeys: [VerseKey], startVerse: VerseKey, endVerse: VerseKey, navigationContext: PageNavigationContext) {
        self.id = UUID()
        self.content = content
        self.verseKeys = verseKeys
        self.startVerse = startVerse
        self.endVerse = endVerse
        self.navigationContext = navigationContext
    }

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

extension GeneratedPage {
    func toOptimizedPageSlice() -> OptimizedPageSlice {
        let content = segments.reduce(into: AttributedString()) { result, seg in
            result += seg.attributed
        }
        let verseKeys = segments.map { $0.verseKey }
        let startVerse = verseKeys.first ?? startKey
        let endVerse = verseKeys.last ?? startKey
        return OptimizedPageSlice(
            content: content,
            verseKeys: verseKeys,
            startVerse: startVerse,
            endVerse: endVerse,
            navigationContext: navigationContext
        )
    }

    func toDatabasePageContent() -> DatabasePageContent {
        let content = segments.reduce(into: AttributedString()) { result, seg in
            result += seg.attributed
        }
        let verseKeys = segments.map { $0.verseKey }
        let startVerse = verseKeys.first ?? startKey
        let endVerse = verseKeys.last ?? startKey

        // Create database verses from verse keys (simplified - would need actual verse text)
        let databaseVerses: [DatabaseVerse] = verseKeys.map { verseKey in
            DatabaseVerse(
                book: verseKey.book,
                chapter: verseKey.chapter,
                verseNumber: verseKey.verse,
                text: "" // This would need to be populated with actual verse text
            )
        }

        // Convert PageNavigationContext to DatabaseNavigationContext
        // Since PageNavigationContext doesn't have detailed navigation info, use defaults
        let dbNavigationContext = DatabaseNavigationContext(
            chapterNumber: startVerse.chapter,
            verseNumber: startVerse.verse,
            totalChapters: 50, // Would need actual book metadata
            totalVerses: 31    // Would need actual chapter metadata
        )

        return DatabasePageContent(
            content: content,
            verses: databaseVerses,
            verseKeys: verseKeys,
            startVerse: startVerse,
            endVerse: endVerse,
            navigationContext: dbNavigationContext,
            startReference: startVerse.description,
            endReference: endVerse.description,
            references: verseKeys.map { $0.description }
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
