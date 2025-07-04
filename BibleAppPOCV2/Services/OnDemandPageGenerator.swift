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

@MainActor
class OnDemandPageGenerator: ObservableObject {
    @Published var currentPage: OptimizedPageSlice?
    @Published var isGenerating = false
    
    private let pageSize: CGSize
    private let pageCache = LRUCache<VerseKey, OptimizedPageSlice>(capacity: 10)
    private var currentPosition: VerseKey?
    private var pendingPartial: (key: VerseKey, text: String)?
    
    init(pageSize: CGSize) {
        self.pageSize = pageSize
    }
    
    // MARK: - Page Generation
    
    func generatePage(startingAt verse: (book: String, chapter: Int, verse: Int)) async {
        let startKey = VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse)
        
        // Check cache first
        if let cachedPage = pageCache.get(startKey) {
            currentPage = cachedPage
            currentPosition = startKey
            return
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        let page = await generatePageContent(startingAt: startKey)
        currentPage = page
        currentPosition = startKey
        
        if let page = page {
            pageCache.set(startKey, page)
            
            // Predictively load next AND previous pages
            Task {
                await predictivelyLoadNextPage(from: page.endVerse)
            }
            
            Task {
                await predictivelyLoadPreviousPage(from: page.startVerse)
            }
        }
    }
    
    func generateNextPage() async {
        guard let current = currentPage else { return }
        
        // Check if we're at the end of a book and need to transition
        if current.navigationContext.isLastVerseOfBook {
            // Find first verse of next book
            if let nextBookVerse = await findFirstVerseOfNextBook(after: current.endVerse.book) {
                await generatePage(startingAt: (nextBookVerse.book, nextBookVerse.chapter, nextBookVerse.verse))
                return
            }
        }
        
        // Otherwise use standard next verse logic
        let nextVerse = await findNextVerse(after: current.endVerse)
        if let next = nextVerse {
            await generatePage(startingAt: (next.book, next.chapter, next.verse))
        }
    }
    
    func generatePreviousPage() async {
        guard let current = currentPage else { return }
        
        // Check if we're at the start of a book and need to transition
        if current.navigationContext.isFirstVerseOfBook {
            // Find last verse of previous book
            if let prevBookVerse = await findLastVerseOfPreviousBook(before: current.startVerse.book) {
                await generatePage(startingAt: (prevBookVerse.book, prevBookVerse.chapter, prevBookVerse.verse))
                return
            }
        }
        
        // Otherwise use standard previous verse logic
        let prevVerse = await findPreviousVerse(before: current.startVerse)
        if let prev = prevVerse {
            await generatePage(startingAt: (prev.book, prev.chapter, prev.verse))
        }
    }
    
    // MARK: - Private Methods
    
    private func generatePageContent(startingAt startKey: VerseKey) async -> OptimizedPageSlice? {
        var currentContent = AttributedString()
        var verseKeys: [VerseKey] = []
        var currentBook = startKey.book
        var currentChapter = startKey.chapter
        var currentVerseIndex = startKey.verse - 1  // 0-based index
        var isFirstVerseOfChapter = true
        var isFirstOfBook = await isFirstVerseOfBook(startKey)

        // If we have leftover text from a previous page starting at the same verse, use it
        var carryOverText: String?
        if let pending = pendingPartial, pending.key == startKey {
            carryOverText = pending.text
            pendingPartial = nil
        }

        // Loop until page is full
        while true {
            // Load current chapter if needed
            guard let chapterContent = await OptimizedBibleDataLoader.shared.loadChapterContent(
                book: currentBook,
                chapter: currentChapter
            ) else {
                break
            }
            
            // Check if we've run out of verses in this chapter
            if currentVerseIndex >= chapterContent.verses.count {
                // Try to move to next chapter
                guard let nextKey = await nextChapterKey(after: currentBook, chapter: currentChapter) else {
                    break // No more chapters available
                }

                // Move to first verse of next chapter
                currentBook = nextKey.book
                currentChapter = nextKey.chapter
                currentVerseIndex = 0
                isFirstVerseOfChapter = true
                let newVerseKey = VerseKey(book: currentBook, chapter: currentChapter, verse: 1)
                if currentBook != startKey.book {
                    isFirstOfBook = await isFirstVerseOfBook(newVerseKey)
                } else {
                    isFirstOfBook = false
                }
                continue
            }
            
            // Process current verse (or remaining text from previous page)
            let verse = chapterContent.verses[currentVerseIndex]
            var verseText = carryOverText ?? verse.text

            let shouldShowChapterHeader = isFirstVerseOfChapter && verse.verse == 1 && carryOverText == nil
            let shouldShowBookTitle = isFirstOfBook && isFirstVerseOfChapter && verse.verse == 1 && carryOverText == nil

            let formatted = JITTextFormatter.formatVerse(
                book: currentBook,
                chapter: currentChapter,
                verse: verse.verse,
                text: verseText,
                showChapterHeader: shouldShowChapterHeader,
                showBookTitle: shouldShowBookTitle
            )
            
            // Check if adding this verse would overflow the page
            let candidateContent = currentContent + formatted
            let size = JITTextFormatter.measureText(candidateContent, maxSize: CGSize(
                width: pageSize.width - 32,  // Apply horizontal margins
                height: pageSize.height - 40  // Apply vertical margins
            ))
            
            if size.height > pageSize.height - 40 {
                // If nothing has been added yet or we are carrying over text, split the verse
                if currentContent.characters.isEmpty || carryOverText != nil {
                    let (partial, remaining) = splitVerse(
                        book: currentBook,
                        chapter: currentChapter,
                        verse: verse.verse,
                        text: verseText,
                        existing: currentContent,
                        showChapterHeader: shouldShowChapterHeader,
                        showBookTitle: shouldShowBookTitle
                    )

                    if !partial.characters.isEmpty {
                        currentContent += partial
                        verseKeys.append(VerseKey(book: currentBook, chapter: currentChapter, verse: verse.verse))
                        pendingPartial = (VerseKey(book: currentBook, chapter: currentChapter, verse: verse.verse), remaining)
                    } else {
                        // Nothing from this verse fits on the current page
                        pendingPartial = (VerseKey(book: currentBook, chapter: currentChapter, verse: verse.verse), verseText)
                    }
                } else {
                    // Page is full, stop here
                    pendingPartial = (VerseKey(book: currentBook, chapter: currentChapter, verse: verse.verse), verseText)
                }
                break
            }

            // Add verse to page
            currentContent = candidateContent
            let verseKey = VerseKey(book: currentBook, chapter: currentChapter, verse: verse.verse)
            verseKeys.append(verseKey)
            
            // Reset flags after using them
            isFirstVerseOfChapter = false
            if isFirstOfBook { isFirstOfBook = false }
            
            // Move to next verse if we consumed the full verse
            if carryOverText == nil {
                currentVerseIndex += 1
            } else {
                // We displayed the remainder of a split verse
                carryOverText = nil
                currentVerseIndex += 1
            }
        }
        
        guard !verseKeys.isEmpty else { return nil }
        
        // Fixed: Correctly check if first/last verses of book
        let firstVerseKey = verseKeys.first!
        let lastVerseKey = verseKeys.last!
        let isFirst = await isFirstVerseOfBook(firstVerseKey)
        let isLast = await isLastVerseOfBook(lastVerseKey)
        
        return OptimizedPageSlice(
            content: currentContent,
            verseKeys: verseKeys,
            startVerse: firstVerseKey,
            endVerse: lastVerseKey,
            navigationContext: PageNavigationContext(
                isFirstVerseOfBook: isFirst,
                isLastVerseOfBook: isLast
            )
        )
    }
    
    // Helper methods for book boundaries
    private func isFirstVerseOfBook(_ verseKey: VerseKey) async -> Bool {
        return verseKey.chapter == 1 && verseKey.verse == 1
    }
    
    private func isLastVerseOfBook(_ verseKey: VerseKey) async -> Bool {
        guard let metadata = await OptimizedBibleDataLoader.shared.metadata else { return false }

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
    func paginateChapter(_ chapter: ChapterContent, font: Font = .body, frameSize: CGSize) -> [Page] {
        var pages: [Page] = []
        var buffer = AttributedString()
        var firstKey: VerseKey?
        var lastKey: VerseKey?

        func commitPage() {
            if let first = firstKey, let last = lastKey, !buffer.characters.isEmpty {
                pages.append(Page(attributedText: buffer, firstVerseKey: first, lastVerseKey: last))
            }
            buffer = AttributedString()
            firstKey = nil
            lastKey = nil
        }

        for verse in chapter.verses {
            let key = VerseKey(book: chapter.book, chapter: chapter.chapter, verse: verse.verse)
            let attributed = JITTextFormatter.formatVerse(book: chapter.book, chapter: chapter.chapter, verse: verse.verse, text: verse.text)

            if firstKey == nil { firstKey = key }
            var candidate = buffer + attributed
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