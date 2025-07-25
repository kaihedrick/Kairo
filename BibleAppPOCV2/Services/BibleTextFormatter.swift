// filepath: BibleAppPOCV2/Services/BibleTextFormatter.swift
// BibleTextFormatter.swift
// Handles the formatting of Bible text according to Crossway typography standards

import Foundation
import SwiftUI

/// Handles Bible text formatting with Crossway-compatible typography
struct BibleTextFormatter {
    
    /// Format a collection of verses into a single AttributedString
    static func formatVerses(_ verses: [(verseKey: VerseKey, text: String)], startingAtFirstVerse: Bool = false) -> AttributedString {
        var result = AttributedString()
        
        for (index, verse) in verses.enumerated() {
            let isFirstVerse = index == 0
            let isFirstVerseOfChapter = verse.verseKey.verse == 1
            let isFirstVerseOfBook = verse.verseKey.chapter == 1 && verse.verseKey.verse == 1
            
            let showBookTitle = isFirstVerse && isFirstVerseOfBook && startingAtFirstVerse
            let showChapterHeader = isFirstVerse && isFirstVerseOfChapter && startingAtFirstVerse
            
            let formatted = JITTextFormatter.formatVerse(
                book: verse.verseKey.book,
                chapter: verse.verseKey.chapter,
                verse: verse.verseKey.verse,
                text: verse.text,
                showChapterHeader: showChapterHeader,
                showBookTitle: showBookTitle
            )
            
            result.append(formatted)
        }
        
        return result
    }
    
    /// Format a single verse according to its context
    static func formatVerse(verseKey: VerseKey, text: String, context: VerseFormattingContext) -> AttributedString {
        return JITTextFormatter.formatVerse(
            book: verseKey.book,
            chapter: verseKey.chapter,
            verse: verseKey.verse,
            text: text,
            showChapterHeader: context.showChapterHeader,
            showBookTitle: context.showBookTitle
        )
    }
    
    /// Create a navigation title for a verse range
    static func navigationTitle(from startVerse: VerseKey, to endVerse: VerseKey) -> String {
        let abbrev = startVerse.book.prefix(3)
        if startVerse.chapter == endVerse.chapter {
            if startVerse.verse == endVerse.verse {
                return "\(abbrev) \(startVerse.chapter):\(startVerse.verse)"
            } else {
                return "\(abbrev) \(startVerse.chapter):\(startVerse.verse)-\(endVerse.verse)"
            }
        } else {
            return "\(abbrev) \(startVerse.chapter):\(startVerse.verse)–\(endVerse.chapter):\(endVerse.verse)"
        }
    }
}

/// Context information for formatting a verse
struct VerseFormattingContext: Codable {
    let showBookTitle: Bool
    let showChapterHeader: Bool
    let isFirstVerseOfPage: Bool
    let isLastVerseOfPage: Bool
    
    init(showBookTitle: Bool = false, showChapterHeader: Bool = false, isFirstVerseOfPage: Bool = false, isLastVerseOfPage: Bool = false) {
        self.showBookTitle = showBookTitle
        self.showChapterHeader = showChapterHeader
        self.isFirstVerseOfPage = isFirstVerseOfPage
        self.isLastVerseOfPage = isLastVerseOfPage
    }
}

/// Determines formatting context for a verse based on its position
struct VerseContextAnalyzer {
    
    /// Analyze the formatting context for a verse
    static func analyzeContext(for verseKey: VerseKey, isFirstInPage: Bool, isLastInPage: Bool) -> VerseFormattingContext {
        let isFirstVerseOfChapter = verseKey.verse == 1
        let isFirstVerseOfBook = verseKey.chapter == 1 && verseKey.verse == 1
        
        let showBookTitle = isFirstInPage && isFirstVerseOfBook
        let showChapterHeader = isFirstInPage && isFirstVerseOfChapter
        
        return VerseFormattingContext(
            showBookTitle: showBookTitle,
            showChapterHeader: showChapterHeader,
            isFirstVerseOfPage: isFirstInPage,
            isLastVerseOfPage: isLastInPage
        )
    }
}
