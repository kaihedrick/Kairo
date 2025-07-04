//
//  OnDemandPageGenerator.swift
//  AIStudyBiblePOC
//
//  Created by Performance Optimization on 6/13/25.
//

import Foundation
import SwiftUI

// MARK: - Optimized Page Models

struct VerseKey: Hashable, Codable {
    let book: String
    let chapter: Int
    let verse: Int
    
    var description: String {
        return "\(book) \(chapter):\(verse)"
    }
}

struct PageNavigationContext: Equatable {
    let isFirstVerseOfBook: Bool
    let isLastVerseOfBook: Bool
}

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

struct GeneratedPage {
    let verses: [VerseContent]
    let startKey: VerseKey
}

// MARK: - Just-in-Time Text Formatter

class JITTextFormatter {
    private static let measurementCache = LRUCache<String, CGSize>(capacity: 100)
    
    static func formatVerse(book: String, chapter: Int, verse: Int, text: String, showChapterHeader: Bool = false, showBookTitle: Bool = false) -> AttributedString {
        var attributed = AttributedString()
        
        // Add book title only on first page of book
        if showBookTitle {
            var bookAttr = AttributedString("\(book)\n\n")
            bookAttr.font = .system(size: 32, weight: .bold)
            bookAttr.foregroundColor = .primary
            attributed.append(bookAttr)
        }
        
        // Add chapter number as inline element for first verse of chapter
        if showChapterHeader {
            var chapterAttr = AttributedString("\(chapter) ")
            chapterAttr.font = .system(size: 28, weight: .bold)
            chapterAttr.foregroundColor = .primary
            
            // Apply background for visual separation
            chapterAttr.backgroundColor = .clear
            attributed.append(chapterAttr)
        }
        
        // Add verse number and text with proper styling
        var verseNumberAttr = AttributedString("\(verse) ")
        verseNumberAttr.font = .system(size: 12, weight: .semibold)
        verseNumberAttr.foregroundColor = .secondary
        
        // Add verse text without extra line breaks to ensure continuous flow
        var verseTextAttr = AttributedString("\(text) ")
        verseTextAttr.font = .body
        verseTextAttr.foregroundColor = .primary

        attributed.append(verseNumberAttr)
        attributed.append(verseTextAttr)

        return attributed
    }
    
    static func measureText(_ text: AttributedString, maxSize: CGSize) -> CGSize {
        if text.characters.isEmpty { return .zero }
        let cacheKey = "\(text.characters.count):\(maxSize.width):\(maxSize.height)"
        
        if let cached = measurementCache.get(cacheKey) {
            return cached
        }
        
        let nsAttr = NSAttributedString(text)
        let drawingOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let drawingRect = nsAttr.boundingRect(
            with: CGSize(width: maxSize.width, height: .greatestFiniteMagnitude),
            options: drawingOptions,
            context: nil
        )
        
        let size = CGSize(width: ceil(drawingRect.width), height: ceil(drawingRect.height))
        measurementCache.set(cacheKey, size)
        
        return size
    }

    static func measureText(_ text: String, maxSize: CGSize) -> CGSize {
        measureText(AttributedString(text), maxSize: maxSize)
    }
    
    static func clearCache() {
        measurementCache.clear()
    }
}

// MARK: - On-Demand Page Generator

actor OnDemandPageGenerator {
    @Published @MainActor private(set) var currentPage: GeneratedPage?
    @Published var isGenerating = false
    @Published var lastError: String?
    
    private let pageSize: CGSize
    private let estimatedLineHeight: CGFloat = 20.0
    private let pageCache = LRUCache<VerseKey, GeneratedPage>(capacity: 10)
    private var currentPosition: VerseKey?
    
    init(pageSize: CGSize) {
        self.pageSize = pageSize
    }
    
    // MARK: - Page Generation
    
    @MainActor
    func generatePage(startingAt verse: (book: String, chapter: Int, verse: Int)) async {
        let startKey = VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse)
        print("🔄 generatePage start for \(startKey)")

        await OptimizedBibleDataLoader.shared.ensureMetadataLoaded()
        lastError = nil
        isGenerating = true
        defer {
            print("🔄 generatePage end for \(startKey) — currentPage set? \((currentPage != nil))")
            isGenerating = false
        }

        if let cached = pageCache.get(startKey) {
            print("📄 Returning cached page for \(startKey)")
            currentPage = cached
            return
        }
        
        guard let page = await generatePageContent(startingAt: startKey) else {
            print("⚠️ generatePageContent returned nil for \(startKey)")
            lastError = "Could not generate page for \(startKey.book) \(startKey.chapter):\(startKey.verse)"
            currentPage = nil
            return
        }
        
        print("✅ Generated new page for \(startKey) with \(page.verses.count) verses")
        currentPage = page
        pageCache.set(startKey, page)
    }
    
    func generateNextPage() async {
        guard let current = currentPage else { return }
        
        // Find the last verse in the current page
        guard let lastVerse = current.verses.last else { return }
        let lastVerseKey = VerseKey(book: current.startKey.book, chapter: current.startKey.chapter, verse: lastVerse.verse)
        
        // Find next verse
        let nextVerse = await findNextVerse(after: lastVerseKey)
        if let next = nextVerse {
            await generatePage(startingAt: (next.book, next.chapter, next.verse))
        }
    }
    
    func generatePreviousPage() async {
        guard let current = currentPage else { return }
        
        // Find previous verse before the start of current page
        let prevVerse = await findPreviousVerse(before: current.startKey)
        if let prev = prevVerse {
            await generatePage(startingAt: (prev.book, prev.chapter, prev.verse))
        }
    }
    
    // MARK: - Private Methods
    
    private func generatePageContent(startingAt startKey: VerseKey) async -> GeneratedPage? {
        print("🔍 generatePageContent start for \(startKey)")
        let chapterContent = await OptimizedBibleDataLoader.shared.loadChapterContent(
            book: startKey.book,
            chapter: startKey.chapter
        )
        
        guard let chapterContent = chapterContent else {
            print("⚠️ No chapter content found for \(startKey)")
            return nil
        }
        
        var pageVerses: [VerseContent] = []
        let maxCount = Int(pageSize.height / estimatedLineHeight)
        var currentVerseIndex = chapterContent.verses.firstIndex { $0.verse == startKey.verse } ?? 0
        
        while currentVerseIndex < chapterContent.verses.count && pageVerses.count < maxCount {
            let verse = chapterContent.verses[currentVerseIndex]
            print("📝 Adding verse \(startKey.book) \(startKey.chapter):\(verse.verse) at index \(currentVerseIndex)")
            pageVerses.append(verse)
            currentVerseIndex += 1
        }
        
        guard !pageVerses.isEmpty else {
            print("⚠️ No verses collected for \(startKey)")
            return nil
        }

        print("📄 generatePageContent returning \(pageVerses.count) verses for \(startKey)")
        return GeneratedPage(verses: pageVerses, startKey: startKey)
    }
    
    // Helper methods for book boundaries
    private func isFirstVerseOfBook(_ verseKey: VerseKey) async -> Bool {
        await OptimizedBibleDataLoader.shared.ensureMetadataLoaded()
        return verseKey.chapter == 1 && verseKey.verse == 1
    }
    
    private func isLastVerseOfBook(_ verseKey: VerseKey) async -> Bool {
        await OptimizedBibleDataLoader.shared.ensureMetadataLoaded()
        guard let metadata = await OptimizedBibleDataLoader.shared.metadata else { 
            // Fallback: assume not last verse if metadata unavailable
            print("⚠️ Warning: Metadata not available for boundary check")
            return false
        }

        guard let bookMeta = metadata.books.first(where: { $0.name == verseKey.book }) else {
            return false
        }
        
        guard let lastChapterContent = await OptimizedBibleDataLoader.shared.loadChapterContent(
            book: verseKey.book,
            chapter: bookMeta.chapterCount
        ) else {
            return false
        }
        
        return verseKey.chapter == bookMeta.chapterCount && 
               verseKey.verse == lastChapterContent.verses.count
    }
    
    // Find the first verse of the next book
    private func findFirstVerseOfNextBook(after bookName: String) async -> VerseKey? {
        guard let metadata = await OptimizedBibleDataLoader.shared.metadata else { return nil }

        guard let currentBookIndex = metadata.books.firstIndex(where: { $0.name == bookName }),
              currentBookIndex + 1 < metadata.books.count else {
            return nil
        }

        let nextBook = metadata.books[currentBookIndex + 1].name
        return VerseKey(book: nextBook, chapter: 1, verse: 1)
    }
    
    // Find the last verse of the previous book
    private func findLastVerseOfPreviousBook(before bookName: String) async -> VerseKey? {
        guard let metadata = await OptimizedBibleDataLoader.shared.metadata else { return nil }

        guard let currentBookIndex = metadata.books.firstIndex(where: { $0.name == bookName }),
              currentBookIndex > 0 else {
            return nil
        }

        let prevBookMeta = metadata.books[currentBookIndex - 1]
        let prevBook = prevBookMeta.name
        let lastChapter = prevBookMeta.chapterCount
        
        guard let chapterContent = await OptimizedBibleDataLoader.shared.loadChapterContent(
            book: prevBook,
            chapter: lastChapter
        ) else {
            return nil
        }
        
        let lastVerse = chapterContent.verses.count
        return VerseKey(book: prevBook, chapter: lastChapter, verse: lastVerse)
    }
    
    private func nextChapterKey(after book: String, chapter: Int) async -> (book: String, chapter: Int)? {
        guard let metadata = await OptimizedBibleDataLoader.shared.metadata else { return nil }

        if let currentBook = metadata.books.first(where: { $0.name == book }) {
            if chapter < currentBook.chapterCount {
                return (book: book, chapter: chapter + 1)
            }
        }

        if let currentIndex = metadata.books.firstIndex(where: { $0.name == book }),
           currentIndex + 1 < metadata.books.count {
            let nextBook = metadata.books[currentIndex + 1]
            return (book: nextBook.name, chapter: 1)
        }

        return nil
    }
    
    private func findNextVerse(after verse: VerseKey) async -> VerseKey? {
        // Simple implementation - in production you'd be more sophisticated
        guard let chapterContent = await OptimizedBibleDataLoader.shared.loadChapterContent(
            book: verse.book,
            chapter: verse.chapter
        ) else { return nil }
        
        if verse.verse < chapterContent.verses.count {
            return VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse + 1)
        }
        
        // Next chapter
        if let nextKey = await nextChapterKey(after: verse.book, chapter: verse.chapter) {
            return VerseKey(book: nextKey.book, chapter: nextKey.chapter, verse: 1)
        }
        
        return nil
    }
    
    private func findPreviousVerse(before verse: VerseKey) async -> VerseKey? {
        if verse.verse > 1 {
            return VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse - 1)
        }
        
        // Previous chapter - simplified implementation
        if verse.chapter > 1 {
            if let prevChapter = await OptimizedBibleDataLoader.shared.loadChapterContent(
                book: verse.book,
                chapter: verse.chapter - 1
            ) {
                return VerseKey(book: verse.book, chapter: verse.chapter - 1, verse: prevChapter.verses.count)
            }
        }
        
        return nil
    }

    private func splitVerse(
        book: String,
        chapter: Int,
        verse: Int,
        text: String,
        existing: AttributedString,
        showChapterHeader: Bool,
        showBookTitle: Bool
    ) -> (AttributedString, String) {
        let words = text.split(separator: " ")
        guard !words.isEmpty else { return (AttributedString(), "") }

        // Phase 1: quickly find a prefix that is likely to fit by adding words sequentially
        var low = 1
        var high = words.count
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            let prefixText = words.prefix(mid).joined(separator: " ")
            let partial = JITTextFormatter.formatVerse(
                book: book,
                chapter: chapter,
                verse: verse,
                text: prefixText,
                showChapterHeader: showChapterHeader,
                showBookTitle: showBookTitle
            )
            let candidate = existing + partial
            let size = JITTextFormatter.measureText(
                candidate,
                maxSize: CGSize(width: pageSize.width - 32, height: pageSize.height - 40)
            )

            if size.height <= pageSize.height - 40 {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        // If no words fit on this page, return empty to indicate overflow
        if best == 0 {
            return (AttributedString(), text)
        }

        let prefix = words.prefix(best).joined(separator: " ")
        let suffix = words.dropFirst(best).joined(separator: " ")
        let prefixAttr = JITTextFormatter.formatVerse(
            book: book,
            chapter: chapter,
            verse: verse,
            text: prefix,
            showChapterHeader: showChapterHeader,
            showBookTitle: showBookTitle
        )

        return (prefixAttr, suffix)
    }
    
    private func predictivelyLoadNextPage(from endVerse: VerseKey) async {
        guard let nextVerse = await findNextVerse(after: endVerse) else { return }
        
        // Generate next page in background if not already cached
        if pageCache.get(nextVerse) == nil {
            let _ = await generatePageContent(startingAt: nextVerse)
        }
    }
    
    private func predictivelyLoadPreviousPage(from startVerse: VerseKey) async {
        guard let prevVerse = await findPreviousVerse(before: startVerse) else { return }
        
        // Generate previous page in background if not already cached
        if pageCache.get(prevVerse) == nil {
            let _ = await generatePageContent(startingAt: prevVerse)
        }
    }
    
    private func predictiveNextChapters(from verseKey: VerseKey) async {
        let book = verseKey.book
        let chapter = verseKey.chapter
        
        async let nextChapter = OptimizedBibleDataLoader.shared.loadChapterContent(
            book: book,
            chapter: chapter + 1
        )
        async let prevChapter = OptimizedBibleDataLoader.shared.loadChapterContent(
            book: book,
            chapter: chapter - 1
        )
        
        // Both will load in parallel and can be awaited when needed
        _ = await nextChapter
        _ = await prevChapter
    }

    // Paginate an entire chapter into discrete pages
    func paginateChapter(_ chapter: OptimizedBible.ChapterContent, font: Font = .body, frameSize: CGSize) -> [GeneratedPage] {
        var pages: [GeneratedPage] = []
        var buffer = AttributedString()
        var firstKey: VerseKey?
        var lastKey: VerseKey?

        func commitPage() {
            if let first = firstKey, let last = lastKey, !buffer.characters.isEmpty {
                pages.append(GeneratedPage(attributedText: buffer, firstVerseKey: first, lastVerseKey: last))
            }
            buffer = AttributedString()
            firstKey = nil
            lastKey = nil
        }

        for verse in chapter.verses {
            let key = VerseKey(book: chapter.book, chapter: chapter.chapter, verse: verse.verse)
            let attributed = JITTextFormatter.formatVerse(book: chapter.book, chapter: chapter.chapter, verse: verse.verse, text: verse.text)

            if firstKey == nil { firstKey = key }
            let candidate = buffer + attributed
            var size = JITTextFormatter.measureText(candidate, maxSize: frameSize)

            if size.height <= frameSize.height {
                buffer = candidate
                lastKey = key
                continue
            }

            // Overflow: binary search for longest prefix that fits
            let words = verse.text.split(separator: " ")
            var low = 0
            var high = words.count
            var best = 0
            while low <= high {
                let mid = (low + high) / 2
                let prefixText = words.prefix(mid).joined(separator: " ")
                let prefixAttr = JITTextFormatter.formatVerse(book: chapter.book, chapter: chapter.chapter, verse: verse.verse, text: prefixText)
                let test = buffer + prefixAttr
                size = JITTextFormatter.measureText(test, maxSize: frameSize)
                if size.height <= frameSize.height {
                    best = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }

            let prefix = words.prefix(best).joined(separator: " ")
            let suffix = words.dropFirst(best).joined(separator: " ")
            let prefixAttr = JITTextFormatter.formatVerse(book: chapter.book, chapter: chapter.chapter, verse: verse.verse, text: prefix)
            buffer += prefixAttr
            lastKey = key
            commitPage()

            if !suffix.isEmpty {
                buffer = JITTextFormatter.formatVerse(book: chapter.book, chapter: chapter.chapter, verse: verse.verse, text: suffix)
                firstKey = key
                lastKey = key
            }
        }

        commitPage()
        return pages
    }
    
    // MARK: - Memory Management
    
    func handleMemoryPressure() {
        pageCache.clear()
        JITTextFormatter.clearCache()
        
        // No need for Task since we're already @MainActor
        autoreleasepool {
            // Any memory-intensive cleanup can go here
        }
    }
}
