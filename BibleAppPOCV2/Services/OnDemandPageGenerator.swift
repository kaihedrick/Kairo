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

@MainActor
class OnDemandPageGenerator: ObservableObject {
    @Published private(set) var currentPage: GeneratedPage?
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?
    
    private let pageSize: CGSize
    private let estimatedLineHeight: CGFloat = 20.0
    private let pageCache = LRUCache<VerseKey, GeneratedPage>(capacity: 10)
    private var currentPosition: VerseKey?
    
    init(pageSize: CGSize) {
        self.pageSize = pageSize
    }
    
    // MARK: - Page Generation
    
    func generatePage(startingAt verse: (book: String, chapter: Int, verse: Int)) async {
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

        // Check cache first
        if let cached = pageCache.get(startKey) {
            print("📄 Returning cached page for \(startKey)")
            currentPage = cached
            return
        }
        
        // Generate page content (this is async work that can be done off main actor)
        guard let page = await generatePageContent(startingAt: startKey) else {
            print("⚠️ generatePageContent returned nil for \(startKey)")
            lastError = "Could not generate page for \(startKey.book) \(startKey.chapter):\(startKey.verse)"
            currentPage = nil
            return
        }
        
        // Update UI state on main actor
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
            print("➡️ Navigating to next page starting at \(next)")
            await generatePage(startingAt: (next.book, next.chapter, next.verse))
        }
    }

    func generatePreviousPage() async {
        guard let current = currentPage else { return }
        
        // Find previous verse before the start of current page
        let prevVerse = await findPreviousVerse(before: current.startKey)
        if let prev = prevVerse {
            print("⬅️ Navigating to previous page starting at \(prev)")
            await generatePage(startingAt: (prev.book, prev.chapter, prev.verse))
        }
    }
    
    // MARK: - Private Methods
    
    nonisolated private func generatePageContent(startingAt startKey: VerseKey) async -> GeneratedPage? {
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
        // Create AttributedString from verses
        var content = AttributedString()
        var verseKeys: [VerseKey] = []
        
        for verse in verses {
            let verseKey = VerseKey(book: startKey.book, chapter: startKey.chapter, verse: verse.verse)
            verseKeys.append(verseKey)
            
            // Format the verse content
            let formatted = JITTextFormatter.formatVerse(
                book: startKey.book,
                chapter: startKey.chapter,
                verse: verse.verse,
                text: verse.text,
                showChapterHeader: verse.verse == 1,
                showBookTitle: startKey.chapter == 1 && verse.verse == 1
            )
            content += formatted
        }
        
        // Calculate start and end verses
        let startVerse = verseKeys.first ?? startKey
        let endVerse = verseKeys.last ?? startKey
        
        // Create navigation context
        let navigationContext = PageNavigationContext(
            isFirstVerseOfBook: startVerse.chapter == 1 && startVerse.verse == 1,
            isLastVerseOfBook: false // This would need proper calculation
        )
        
        return OptimizedPageSlice(
            content: content,
            verseKeys: verseKeys,
            startVerse: startVerse,
            endVerse: endVerse,
            navigationContext: navigationContext
        )
    }
}
