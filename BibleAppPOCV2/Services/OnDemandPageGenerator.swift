//
//  OnDemandPageGenerator.swift
//  AIStudyBiblePOC
//
//  Created by Performance Optimization on 6/13/25.
//

import Foundation
import SwiftUI

// Shared models and text formatter lives in separate files for reuse
// across views and generators.

// MARK: - On-Demand Page Generator

/// Specific reasons page generation can fail.
enum PageGenerationError: Error {
    case noChapterContent(VerseKey)
    case noSegments(VerseKey)
}

@MainActor
class OnDemandPageGenerator: ObservableObject {
    @Published private(set) var currentPage: GeneratedPage?
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?
    
    private let pageSize: CGSize
    private let pageCache = LRUCache<VerseKey, GeneratedPage>(capacity: 10)
    private var pendingRemainder: (key: VerseKey, text: AttributedString)?
    private var pageHistory: [VerseKey] = []

    /// Padding applied to the text container in `BibleReaderView.pageView`
    /// which reduces the actual area available for verse text.
    /// These values should stay in sync with the view layout to ensure
    /// pagination calculations closely match on-screen rendering.
    private let verticalPadding: CGFloat = 24   // top + bottom in pageView
    private let horizontalPadding: CGFloat = 32 // left + right in pageView
    
    init(pageSize: CGSize) {
        self.pageSize = pageSize
    }
    
    // MARK: - Page Generation
    
    func generatePage(startingAt verse: (book: String, chapter: Int, verse: Int), storeInHistory: Bool = true) async {
        let startKey = VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse)
        print("🔄 generatePage start for \(startKey)")

        // Ensure metadata is loaded first (this is async work)
        await OptimizedBibleDataLoader.shared.ensureMetadataLoaded()
        
        // Update UI state on main actor
        lastError = nil
        isGenerating = true
        defer {
            print("🔄 generatePage end for \(startKey) — currentPage set? \((currentPage != nil))")
            isGenerating = false
        }

        if storeInHistory {
            if pageHistory.last != startKey {
                pageHistory.append(startKey)
            }
        }

        // Use cache only when no partial text is pending
        if pendingRemainder == nil, let cached = pageCache.get(startKey) {
            print("📄 Returning cached page for \(startKey)")
            currentPage = cached
            return
        }

        // Determine if we have leftover text for this verse
        let initialRemainder = (pendingRemainder?.key == startKey) ? pendingRemainder?.text : nil
        pendingRemainder = nil

        // Generate page content (this is async work that can be done off main actor)
        let generationResult = await generatePageContent(startingAt: startKey, initialRemainder: initialRemainder)
        switch generationResult {
        case .failure(let error):
            print("⚠️ generatePageContent failed for \(startKey) with \(error)")
            switch error {
            case .noChapterContent:
                lastError = "Missing chapter data for \(startKey.book) \(startKey.chapter)"
            case .noSegments:
                lastError = "No text could be rendered for \(startKey.book) \(startKey.chapter):\(startKey.verse)"
            }
            currentPage = nil
            return
        case .success(let result):
            let page = result.page
            pendingRemainder = result.remainder

            // Update UI state on main actor
            print("✅ Generated new page for \(startKey) with \(page.segments.count) segments")
            currentPage = page
            if initialRemainder == nil && result.remainder == nil {
                pageCache.set(startKey, page)
            }

            Task { [weak self, page, result = pendingRemainder] in
                guard let self else { return }
                await self.prefetchNextPage(from: page, remainder: result)
            }
        }
    }
    
    func generateNextPage() async {
        if let pending = pendingRemainder {
            await generatePage(startingAt: (pending.key.book, pending.key.chapter, pending.key.verse))
            return
        }

        guard let current = currentPage else { return }

        // Find the last verse displayed on the current page
        guard let lastKey = current.segments.last?.verseKey else { return }

        // Find next verse
        let nextVerse = await findNextVerse(after: lastKey)
        if let next = nextVerse {
            print("➡️ Navigating to next page starting at \(next)")
            await generatePage(startingAt: (next.book, next.chapter, next.verse))
        }
    }

    func generatePreviousPage() async {
        guard pageHistory.count >= 2 else { return }
        // Remove current page key
        pageHistory.removeLast()
        guard let prev = pageHistory.last else { return }
        print("⬅️ Navigating to previous page starting at \(prev)")
        await generatePage(startingAt: (prev.book, prev.chapter, prev.verse), storeInHistory: false)
    }
    
    // MARK: - Private Methods
    
    nonisolated private func generatePageContent(
        startingAt startKey: VerseKey,
        initialRemainder: AttributedString? = nil
    ) async -> Result<(page: GeneratedPage, remainder: (key: VerseKey, text: AttributedString)?), PageGenerationError> {
        print("🔍 generatePageContent start for \(startKey)")
        let chapterContent = await OptimizedBibleDataLoader.shared.loadChapterContent(
            book: startKey.book,
            chapter: startKey.chapter
        )
        
        guard let chapterContent = chapterContent else {
            print("⚠️ No chapter content found for \(startKey)")
            return .failure(.noChapterContent(startKey))
        }
        
        let availableHeight = max(pageSize.height - verticalPadding, 0)
        let availableWidth = max(pageSize.width - horizontalPadding, 0)

        var segments: [PageSegment] = []
        var currentHeight: CGFloat = 0
        var remainder: (key: VerseKey, text: AttributedString)?

        var currentVerseIndex = chapterContent.verses.firstIndex { $0.verse == startKey.verse } ?? 0

        if var remaining = initialRemainder, !remaining.characters.isEmpty {
            let size = JITTextFormatter.measureText(remaining, maxSize: CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
            if size.height > availableHeight {
                let (fit, tail) = JITTextFormatter.split(attributed: remaining, maxSize: CGSize(width: availableWidth, height: availableHeight))
                segments.append(PageSegment(attributed: fit, verseKey: startKey))
                remainder = (startKey, tail)
                let nav = PageNavigationContext(
                    isFirstVerseOfBook: await isFirstVerseOfBook(startKey),
                    isLastVerseOfBook: await isLastVerseOfBook(startKey)
                )
                let page = GeneratedPage(segments: segments, startKey: startKey, navigationContext: nav)
                return .success((page: page, remainder: remainder))
            } else {
                segments.append(PageSegment(attributed: remaining, verseKey: startKey))
                currentHeight += size.height
                currentVerseIndex += 1
            }
        }

        while currentVerseIndex < chapterContent.verses.count {
            let verse = chapterContent.verses[currentVerseIndex]

            let formatted = JITTextFormatter.formatVerse(
                book: startKey.book,
                chapter: startKey.chapter,
                verse: verse.verse,
                text: verse.text,
                showChapterHeader: verse.verse == 1 && segments.isEmpty,
                showBookTitle: startKey.chapter == 1 && verse.verse == 1 && segments.isEmpty
            )
            let verseSize = JITTextFormatter.measureText(
                formatted,
                maxSize: CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
            )
            if segments.isEmpty {
                print("first-verse H=\(verseSize.height)  budget=\(availableHeight)")
            }

            if currentHeight + verseSize.height <= availableHeight {
                segments.append(PageSegment(attributed: formatted, verseKey: VerseKey(book: startKey.book, chapter: startKey.chapter, verse: verse.verse)))
                currentHeight += verseSize.height
                currentVerseIndex += 1
            } else {
                let headSpace = availableHeight - currentHeight
                if headSpace > 0 {
                    let (fit, tail) = JITTextFormatter.split(attributed: formatted, maxSize: CGSize(width: availableWidth, height: headSpace))
                    if !fit.characters.isEmpty {
                        segments.append(PageSegment(attributed: fit, verseKey: VerseKey(book: startKey.book, chapter: startKey.chapter, verse: verse.verse)))
                    }
                    remainder = (VerseKey(book: startKey.book, chapter: startKey.chapter, verse: verse.verse), tail)
                } else if segments.isEmpty {
                    // *** safety: never return 0 slices ***
                    segments.append(PageSegment(attributed: formatted, verseKey: VerseKey(book: startKey.book, chapter: startKey.chapter, verse: verse.verse)))
                    currentVerseIndex += 1
                }
                break
            }
        }

        if segments.isEmpty {
            print("⚠️ No segments collected for \(startKey) - using preview text")
            let preview = chapterContent.verses.first(where: { $0.verse == startKey.verse })?.text.prefix(120) ?? ""
            let fallback = AttributedString(String(preview) + "…")
            segments.append(PageSegment(attributed: fallback, verseKey: startKey))
        }

        print("📄 generatePageContent returning \(segments.count) segments for \(startKey)")

        let firstKey = segments.first?.verseKey ?? startKey
        let lastKey = segments.last?.verseKey ?? startKey
        let navContext = PageNavigationContext(
            isFirstVerseOfBook: await isFirstVerseOfBook(firstKey),
            isLastVerseOfBook: await isLastVerseOfBook(lastKey)
        )

        let page = GeneratedPage(segments: segments, startKey: startKey, navigationContext: navContext)
        return .success((page: page, remainder: remainder))
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

    private func prefetchNextPage(from page: GeneratedPage, remainder: (key: VerseKey, text: AttributedString)?) async {
        let startKey: VerseKey?
        let tail: AttributedString?
        if let remainder = remainder {
            startKey = remainder.key
            tail = remainder.text
        } else if let lastKey = page.segments.last?.verseKey {
            startKey = await findNextVerse(after: lastKey)
            tail = nil
        } else {
            startKey = nil
            tail = nil
        }

        guard let key = startKey else { return }
        if pageCache.get(key) != nil { return }

        let result = await generatePageContent(startingAt: key, initialRemainder: tail)
        if case .success(let pageResult) = result {
            if pageResult.remainder == nil {
                pageCache.set(key, pageResult.page)
            }
        }
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

// MARK: - GeneratedPage Extensions

extension GeneratedPage {
    /// Convert GeneratedPage to OptimizedPageSlice for SwiftUI compatibility
    func toOptimizedPageSlice() -> OptimizedPageSlice {
        var content = AttributedString()
        var verseKeys: [VerseKey] = []

        for segment in segments {
            if verseKeys.last != segment.verseKey {
                verseKeys.append(segment.verseKey)
            }
            content += segment.attributed
        }

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
}
