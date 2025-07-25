// filepath: BibleAppPOCV2/Services/PageFormatter.swift
//
//  PageFormatter.swift
//  BibleAppPOCV2
//
//  Created by refactoring from OnDemandPageGenerator.swift
//  Handles text formatting for Bible verses, chapters, and titles
//

import Foundation
import SwiftUI

/// Handles formatting of Bible text for display
final class PageFormatter {
    
    /// Format a complete verse with optional headers
    static func formatVerse(
        book: String,
        chapter: Int,
        verse: Int,
        text: String,
        showChapterHeader: Bool = false,
        showBookTitle: Bool = false
    ) -> AttributedString {
        return JITTextFormatter.formatVerse(
            book: book,
            chapter: chapter,
            verse: verse,
            text: text,
            showChapterHeader: showChapterHeader,
            showBookTitle: showBookTitle
        )
    }
    
    /// Format a chapter header
    static func formatChapterLabel(chapter: Int) -> AttributedString {
        var chapterAttr = AttributedString("\(chapter)")
        chapterAttr.font = Typography.chapter
        chapterAttr.foregroundColor = .primary
        return chapterAttr
    }
    
    /// Format a book title
    static func formatBookTitle(book: String) -> AttributedString {
        var bookAttr = AttributedString(book)
        bookAttr.font = Typography.bookTitle
        bookAttr.foregroundColor = .primary
        return bookAttr
    }
    
    /// Format a verse number with superscript styling
    static func formatVerseNumber(verse: Int) -> AttributedString {
        var verseNumberAttr = AttributedString("\(verse)")
        verseNumberAttr.font = Typography.verseNumber
        verseNumberAttr.foregroundColor = .secondary
        verseNumberAttr.baselineOffset = 0 // Typography doesn't have verseNumberBaselineOffset
        return verseNumberAttr
    }
    
    /// Format verse text with body font
    static func formatVerseText(_ text: String) -> AttributedString {
        var verseTextAttr = AttributedString(text)
        verseTextAttr.font = Typography.body
        verseTextAttr.foregroundColor = .primary
        return verseTextAttr
    }
    
    /// Create a combined book title and chapter header
    static func formatCombinedBookAndChapter(book: String, chapter: Int) -> AttributedString {
        let combinedText = "\(book)\n\(chapter)\n\n"
        var combinedAttr = AttributedString(combinedText)
        
        // Apply book title font to the book name part
        let bookStart = combinedAttr.startIndex
        let bookEnd = combinedAttr.index(bookStart, offsetByCharacters: book.count)
        let bookRange = bookStart..<bookEnd
        combinedAttr[bookRange].font = Typography.bookTitle
        combinedAttr[bookRange].foregroundColor = .primary
        
        // Apply chapter font to the chapter number part
        let chapterStart = combinedAttr.index(bookEnd, offsetByCharacters: 1) // Skip the newline
        let chapterEnd = combinedAttr.index(chapterStart, offsetByCharacters: String(chapter).count)
        let chapterRange = chapterStart..<chapterEnd
        combinedAttr[chapterRange].font = Typography.chapter
        combinedAttr[chapterRange].foregroundColor = .primary
        
        return combinedAttr
    }
}
