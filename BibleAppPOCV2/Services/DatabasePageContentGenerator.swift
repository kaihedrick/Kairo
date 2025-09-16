// filepath: BibleAppPOCV2/Services/DatabasePageContentGenerator.swift
//
//  DatabasePageContentGenerator.swift
//  BibleAppPOCV2
//
//  Database-backed version of PageContentGenerator
//  Handles page content generation using SQLite database
//

import Foundation
import SwiftUI
import CoreGraphics

// MARK: - Database Page Content Generator

/// Database-backed version of PageContentGenerator that uses SQLite instead of JSON
@MainActor
final class DatabasePageContentGenerator {
    static let shared = DatabasePageContentGenerator()

    private let dataLoader: DatabaseBibleDataLoader

    private init(dataLoader: DatabaseBibleDataLoader? = nil) {
        self.dataLoader = dataLoader ?? DatabaseBibleDataLoader()
    }

    /// Generate page content starting from a specific verse using database
    func generate(
        from key: VerseKey,
        pageSize: CGSize,
        tail: AttributedString? = nil
    ) async -> Result<(page: DatabaseGeneratedPage, remainder: (key: VerseKey, text: AttributedString)?), DatabasePageGenerationError> {

        let result = await dataLoader.loadChapter(book: key.book, chapter: key.chapter)
        guard case .success(let chapter) = result else {
            return .failure(.missingChapter(key))
        }

        guard pageSize.width > 0 && pageSize.height > 0 else {
            return .failure(.layoutFailed(key))
        }

        #if DEBUG
        print("📖 DatabasePageContentGenerator: Starting page at \(key.description) with size \(pageSize)")
        #endif

        let startVerseIndex = chapter.verses.firstIndex { $0.verseNumber == key.verse } ?? 0

        // PRECISION-FIRST PAGINATION: Use exact SwiftUI Text rendering measurements
        // WHY: Eliminates the overflow feedback loop and ensures headers show exactly visible verses

        // Calculate available height with extra conservative margin to prevent any overflow
        let conservativeMargin: CGFloat = 20 // Extra safety margin for SwiftUI rendering variations
        let availableHeight = pageSize.height - (LayoutMetrics.verticalPagePadding * 2) - conservativeMargin
        let maxSize = CGSize(width: pageSize.width - (LayoutMetrics.horizontalPagePadding * 2), height: availableHeight)

        #if DEBUG
        print("📏 DatabasePageContentGenerator: available=\(availableHeight), maxWidth=\(maxSize.width)")
        #endif

        var segments: [DatabasePageSegment] = []

        // Add carryover text if present
        if let tail = tail, !tail.characters.isEmpty {
            segments.append(.carryover(tail))
        }

        // Add book title if this is the first chapter
        if key.chapter == 1 && segments.isEmpty {
            let bookTitle = JITTextFormatter.formatBookTitle(book: key.book)
            segments.append(.header(bookTitle))
        }

        // Add chapter header if starting at verse 1
        if key.verse == 1 {
            let chapterHeader = JITTextFormatter.formatChapterHeader(book: key.book, chapter: key.chapter)
            segments.append(.header(chapterHeader))
        }

        var currentHeight: CGFloat = segments.reduce(0) { $0 + measureSegmentHeight($1, maxSize: maxSize) }
        var lastVerseKey: VerseKey? = nil

        // Add verses until we exceed available height
        for i in startVerseIndex..<chapter.verses.count {
            let verse = chapter.verses[i]

            // Create verse key for this verse
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verseNumber)
            lastVerseKey = verseKey

            // Format the verse
            let verseText = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verseNumber,
                text: verse.text,
                showChapterHeader: false,
                showBookTitle: false
            )

            // Measure if this verse would fit
            let verseHeight = measureAttributedStringHeight(verseText, maxSize: maxSize)

            #if DEBUG
            print("📏 Verse \(verse.verseNumber): height=\(verseHeight), current=\(currentHeight), available=\(availableHeight)")
            #endif

            if currentHeight + verseHeight > availableHeight {
                // This verse would exceed the page, create remainder
                let remainderKey = verseKey
                let remainderText = verseText

                #if DEBUG
                print("✂️ DatabasePageContentGenerator: Page break at verse \(verse.verseNumber)")
                #endif

                return .success((
                    page: DatabaseGeneratedPage(
                        content: segments,
                        startKey: key,
                        endKey: lastVerseKey ?? key,
                        measuredHeight: currentHeight,
                        availableHeight: availableHeight
                    ),
                    remainder: (key: remainderKey, text: remainderText)
                ))
            }

            // Add verse to page
            segments.append(.verse(verseKey, verseText))
            currentHeight += verseHeight
        }

        // All verses fit, no remainder
        #if DEBUG
        print("✅ DatabasePageContentGenerator: All verses fit on page")
        #endif

        return .success((
            page: DatabaseGeneratedPage(
                content: segments,
                startKey: key,
                endKey: lastVerseKey ?? key,
                measuredHeight: currentHeight,
                availableHeight: availableHeight
            ),
            remainder: nil
        ))
    }

    /// Measure height of an attributed string within given size constraints
    private func measureAttributedStringHeight(_ text: AttributedString, maxSize: CGSize) -> CGFloat {
        let nsAttributedString = NSAttributedString(text)
        let textStorage = NSTextStorage(attributedString: nsAttributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: maxSize)

        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        layoutManager.glyphRange(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)

        return ceil(usedRect.height)
    }

    /// Measure height of a page segment
    private func measureSegmentHeight(_ segment: DatabasePageSegment, maxSize: CGSize) -> CGFloat {
        switch segment {
        case .header(let text), .verse(_, let text), .carryover(let text):
            return measureAttributedStringHeight(text, maxSize: maxSize)
        }
    }
}

// MARK: - Supporting Types

/// Page segment types for content generation
enum DatabasePageSegment {
    case header(AttributedString)
    case verse(VerseKey, AttributedString)
    case carryover(AttributedString)
}

/// Database-backed page result
struct DatabaseGeneratedPage {
    let content: [DatabasePageSegment]
    let startKey: VerseKey
    let endKey: VerseKey
    let measuredHeight: CGFloat
    let availableHeight: CGFloat

    /// Convert to attributed string for display
    var attributedString: AttributedString {
        var result = AttributedString()
        for segment in content {
            switch segment {
            case .header(let text), .verse(_, let text), .carryover(let text):
                result += text
            }
        }
        return result
    }
}

/// Database page generation errors
enum DatabasePageGenerationError: Error {
    case missingChapter(VerseKey)
    case layoutFailed(VerseKey)
    case databaseError(String)
}

// MARK: - Extensions

extension VerseKey {
    /// Get next verse in sequence
    func next() -> VerseKey {
        return VerseKey(book: book, chapter: chapter, verse: verse + 1)
    }

    /// Get previous verse in sequence
    func previous() -> VerseKey {
        return VerseKey(book: book, chapter: chapter, verse: max(1, verse - 1))
    }
}
