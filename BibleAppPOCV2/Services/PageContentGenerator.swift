// filepath: BibleAppPOCV2/Services/PageContentGenerator.swift
//
//  PageContentGenerator.swift
//  BibleAppPOCV2
//
//  Created by refactoring from OnDemandPageGenerator.swift
//  Handles page content generation and formatting logic
//

import Foundation
import SwiftUI
import CoreGraphics

/// Handles the generation of page content from Bible data
@MainActor
final class PageContentGenerator {
    static let shared = PageContentGenerator()
    
    private init() {}
    
    /// Generate page content starting from a specific verse
    static func generate(
        from key: VerseKey,
        pageSize: CGSize,
        tail: AttributedString? = nil,
        using loader: DatabaseBibleDataLoader
    ) async -> Result<(page: GeneratedPage, remainder: (key: VerseKey, text: AttributedString)?), PageGenerationError> {
        
        let result = await loader.loadChapter(book: key.book, chapter: key.chapter)
        guard case .success(let chapter) = result else {
            return .failure(.missingChapter(key))
        }
        
        guard pageSize.width > 0 && pageSize.height > 0 else {
            return .failure(.layoutFailed(key))
        }
        
        print("📖 DYNAMIC HEIGHT: Starting page at \(key.description) with size \(pageSize)")
        
        let startVerseIndex = chapter.verses.firstIndex { $0.verseNumber == key.verse } ?? 0

        #if DEBUG
        print("🎯 PAGE GENERATION: Starting at verse \(key.verse), found index \(startVerseIndex)")
        print("📚 CHAPTER INFO: \(chapter.verses.count) total verses, starting from index \(startVerseIndex)")
        if startVerseIndex < chapter.verses.count {
            let startVerse = chapter.verses[startVerseIndex]
            print("🎯 START VERSE: \(startVerse.verseNumber) - '\(startVerse.text.prefix(50))...'")
        }
        #endif

        // PRECISION-FIRST PAGINATION: Use exact SwiftUI Text rendering measurements
        // WHY: Eliminates the overflow feedback loop and ensures headers show exactly visible verses

        // Calculate available height with MORE GENEROUS margin to allow multiple verses per page
        let conservativeMargin: CGFloat = 20 // Extra safety margin for SwiftUI rendering variations
        let availableHeight = pageSize.height - (LayoutMetrics.verticalPagePadding * 2) - conservativeMargin
        let maxSize = CGSize(width: pageSize.width - (LayoutMetrics.horizontalPagePadding * 2), height: availableHeight)

        print("📏 PRECISE LAYOUT: available=\(availableHeight), maxWidth=\(maxSize.width)")
        print("📏 Page size: \(pageSize.width) x \(pageSize.height), margins: \(LayoutMetrics.horizontalPagePadding)h + \(LayoutMetrics.verticalPagePadding)v")
        
        var segments: [PageSegment] = []
        var accumulatedHeight: CGFloat = 0  // ✅ Reset per page
        var lastCompleteVerseIndex = startVerseIndex - 1

        #if DEBUG
        print("🔄 PAGE ACCUMULATORS RESET:")
        print("   accumulatedHeight: \(accumulatedHeight)")
        print("   maxAllowed: \(availableHeight * 0.90)")
        print("   heightLimit: \(availableHeight * 0.90)")
        #endif
        
        // Add carryover segment if there was one
        if let carryover = tail, !carryover.characters.isEmpty {
            let carryoverHeight = JITTextFormatter.measureText(carryover, maxSize: maxSize).height
            // Use same 90% limit for consistency
            if accumulatedHeight + carryoverHeight <= availableHeight * 0.90 {
                segments.append(PageSegment(attributed: carryover, verseKey: key, isSplit: true))
                accumulatedHeight += carryoverHeight
                print("📏 Added carryover: height=\(carryoverHeight), total=\(accumulatedHeight)")
            } else {
                print("🚫 Carryover too tall, skipping: \(carryoverHeight) > \(availableHeight * 0.90)")
            }
        }
        
        // Accumulate verses with CONSERVATIVE height checking to prevent any overflow
        #if DEBUG
        print("🔄 STARTING VERSE ACCUMULATION: from verse \(chapter.verses[startVerseIndex].verseNumber) (\(chapter.verses.count - startVerseIndex) verses available)")
        #endif

        for i in startVerseIndex..<chapter.verses.count {
            let verse = chapter.verses[i]
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verseNumber)

            #if DEBUG
            print("🔍 PROCESSING VERSE \(verse.verseNumber): '\(verse.text.prefix(30))...'")
            #endif

            var formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verseNumber,
                text: verse.text,
                showChapterHeader: false,
                showBookTitle: false
            )

            // If this is the first visible verse and it's verse 1 of the chapter,
            // just prepend a chapter glyph and keep verse 1 *exactly as formatted*.
            if verse.verseNumber == 1 {
                let chapterGlyph = Self.makeInlineChapterGlyph(chapter: key.chapter, baseAttributes: nil)
                let hair = AttributedString("\u{200A}") // narrow space after the big chapter number
                formatted = chapterGlyph + hair + formatted
            }

            // Measure this verse's actual height
            let verseHeight = JITTextFormatter.measureText(formatted, maxSize: maxSize).height

            // LESS CONSERVATIVE CHECK: Use 90% of available height to allow more verses per page
            let heightLimit = availableHeight * 0.90
            if accumulatedHeight + verseHeight <= heightLimit {
                segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
                accumulatedHeight += verseHeight
                lastCompleteVerseIndex = i
                print("📏 Added verse \(verse.verseNumber): height=\(String(format: "%.1f", verseHeight)), total=\(String(format: "%.1f", accumulatedHeight))/\(String(format: "%.1f", heightLimit)) (90% limit)")
            } else {
                print("🛑 PAGINATION STOP: Verse \(verse.verseNumber) would exceed 90% limit (\(String(format: "%.1f", verseHeight)) needed, \(String(format: "%.1f", heightLimit - accumulatedHeight)) available)")
                break
            }
        }

        #if DEBUG
        print("📊 PAGE ACCUMULATION COMPLETE: \(segments.count) verses, height \(String(format: "%.1f", accumulatedHeight))")
        let verseNumbers = segments.map { $0.verseKey.verse }
        print("📋 VERSE NUMBERS: \(verseNumbers)")
        #endif
        
        // Emergency fallback - ensure we have at least one verse
        if segments.isEmpty {
            let verse = chapter.verses[startVerseIndex]
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verseNumber)
            
            let formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verseNumber,
                text: verse.text,
                showChapterHeader: false,
                showBookTitle: false
            )
            
            segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
            lastCompleteVerseIndex = startVerseIndex
            print("🚨 Emergency fallback: added verse \(verse.verseNumber) (page must have at least one verse)")
        }
        
        // Handle remainder — continue within chapter when possible,
        // otherwise advance to the next chapter/book (no looping)
        let remainder: (key: VerseKey, text: AttributedString)?
        let nextVerseIndex = lastCompleteVerseIndex + 1
        if nextVerseIndex < chapter.verses.count {
            let nextVerse = chapter.verses[nextVerseIndex]
            remainder = (key: VerseKey(book: key.book, chapter: key.chapter, verse: nextVerse.verseNumber), text: AttributedString())
        } else {
            // We ended at the last verse of this chapter — jump across chapters/books
            if let jump = await nextChapterStart(after: VerseKey(book: key.book, chapter: key.chapter, verse: chapter.verses.last?.verseNumber ?? 1), using: loader) {
                remainder = (key: jump, text: AttributedString())
            } else {
                remainder = nil // end of canon (Revelation)
            }
        }
        
        let startVerse = chapter.verses[startVerseIndex]
        let endVerse = chapter.verses[lastCompleteVerseIndex]
        
        let page = GeneratedPage(
            segments: segments,
            startKey: VerseKey(book: key.book, chapter: key.chapter, verse: startVerse.verseNumber),
            navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false)
        )
        
        print("📄 PRECISION RESULT: verses \(startVerse.verseNumber)-\(endVerse.verseNumber) (\(segments.count) verses)")
        print("📄 Height used: \(String(format: "%.1f", accumulatedHeight)) of \(String(format: "%.1f", availableHeight * 0.90)) limit (90%)")
        print("📄 Actual available space: \(String(format: "%.1f", availableHeight)) (with \(conservativeMargin)pt safety margin)")
        print("📄 Has remainder: \(remainder != nil)")
        if remainder == nil { print("📘 Reached end of chapter and no next chapter/book — end of canon or data gap") }
        if let r = remainder {
            print("📄 Next page starts at: \(r.key.description)")
        }
        
        return .success((page: page, remainder: remainder))
    }
    
    // MARK: - Helper Functions for Inline Chapter Glyph
    
    // Build an inline chapter glyph (big numeral) borrowing base attributes
    private static func makeInlineChapterGlyph(chapter: Int, baseAttributes: AttributeContainer? = nil) -> AttributedString {
        var attrs = AttributeContainer()
        if let base = baseAttributes { attrs.merge(base) }
        attrs.font = .system(size: 20, weight: .bold, design: .default) // tweak to taste
        attrs.baselineOffset = 2
        var s = AttributedString(String(chapter))
        s.mergeAttributes(attrs)
        return s
    }

}

// MARK: - Canon (Protestant, 66 books)
private let CANON_BOOKS: [String] = [
    // OT
    "Genesis","Exodus","Leviticus","Numbers","Deuteronomy","Joshua","Judges","Ruth",
    "1 Samuel","2 Samuel","1 Kings","2 Kings","1 Chronicles","2 Chronicles","Ezra","Nehemiah",
    "Esther","Job","Psalms","Proverbs","Ecclesiastes","Song of Solomon","Isaiah","Jeremiah",
    "Lamentations","Ezekiel","Daniel","Hosea","Joel","Amos","Obadiah","Jonah",
    "Micah","Nahum","Habakkuk","Zephaniah","Haggai","Zechariah","Malachi",
    // NT
    "Matthew","Mark","Luke","John","Acts","Romans","1 Corinthians","2 Corinthians",
    "Galatians","Ephesians","Philippians","Colossians","1 Thessalonians","2 Thessalonians",
    "1 Timothy","2 Timothy","Titus","Philemon","Hebrews","James","1 Peter","2 Peter",
    "1 John","2 John","3 John","Jude","Revelation"
]

// Optional: simple aliases → canonical name (edit if your DB uses alternates)
private let BOOK_ALIASES: [String: String] = [
    "Song of Songs": "Song of Solomon",
    "Canticles": "Song of Solomon",
    "Apocalypse": "Revelation",
    "Revelations": "Revelation"
]

private func normalizeBook(_ name: String) -> String {
    if let canon = BOOK_ALIASES[name] { return canon }
    return name
}

private func nextCanonBook(after name: String) -> String? {
    let n = normalizeBook(name)
    guard let i = CANON_BOOKS.firstIndex(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { return nil }
    let j = i + 1
    return j < CANON_BOOKS.count ? CANON_BOOKS[j] : nil
}

private func prevCanonBook(before name: String) -> String? {
    let n = normalizeBook(name)
    guard let i = CANON_BOOKS.firstIndex(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { return nil }
    let j = i - 1
    return j >= 0 ? CANON_BOOKS[j] : nil
}

// Probe what exists via the loader
private func chapterExists(book: String, chapter: Int, using loader: DatabaseBibleDataLoader) async -> Bool {
    guard chapter >= 1 else { return false }
    switch await loader.loadChapter(book: book, chapter: chapter) {
    case .success: return true
    case .failure: return false
    }
}

private func lastChapterNumber(in book: String, using loader: DatabaseBibleDataLoader) async -> Int? {
    var ch = 1, last: Int? = nil
    while await chapterExists(book: book, chapter: ch, using: loader) { last = ch; ch += 1 }
    return last
}

private func lastVerseNumber(book: String, chapter: Int, using loader: DatabaseBibleDataLoader) async -> Int? {
    switch await loader.loadChapter(book: book, chapter: chapter) {
    case .success(let ch):
        return ch.verses.last?.verseNumber
    case .failure:
        return nil
    }
}

/// Next chapter start (1st verse) across books when needed
private func nextChapterStart(after key: VerseKey, using loader: DatabaseBibleDataLoader) async -> VerseKey? {
    let book = normalizeBook(key.book)
    // Same book, next chapter?
    if await chapterExists(book: book, chapter: key.chapter + 1, using: loader) {
        return VerseKey(book: book, chapter: key.chapter + 1, verse: 1)
    }
    // Next book, chapter 1?
    if let nb = nextCanonBook(after: book), await chapterExists(book: nb, chapter: 1, using: loader) {
        return VerseKey(book: nb, chapter: 1, verse: 1)
    }
    return nil // end of canon (Revelation)
}

/// Previous chapter end (last verse) across books when needed
private func previousChapterLastVerse(before key: VerseKey, using loader: DatabaseBibleDataLoader) async -> VerseKey? {
    let book = normalizeBook(key.book)
    if key.chapter > 1 {
        let prevCh = key.chapter - 1
        if let lv = await lastVerseNumber(book: book, chapter: prevCh, using: loader) {
            return VerseKey(book: book, chapter: prevCh, verse: lv)
        }
    } else if let pb = prevCanonBook(before: book), let lastCh = await lastChapterNumber(in: pb, using: loader), let lv = await lastVerseNumber(book: pb, chapter: lastCh, using: loader) {
        return VerseKey(book: pb, chapter: lastCh, verse: lv)
    }
    return nil // beginning of canon (Genesis 1:1)
}
