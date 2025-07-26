// filepath: BibleAppPOCV2/Services/FragmentedPageNavigationManager.swift
//
//  FragmentedPageNavigationManager.swift
//  BibleAppPOCV2
//
//  Enhanced backward navigation manager for fragmented pages
//  Implements reliable page history snapshots to prevent guess-based navigation
//

import Foundation
import SwiftUI

/// Enhanced navigation manager for fragmented pages with reliable backward navigation
@MainActor
final class FragmentedPageNavigationManager: ObservableObject {
    private let loader: OptimizedBibleDataLoader
    private let historyService = PageHistoryService()
    private let pageSize: CGSize
    private var isNavigatingFromHistory = false

    // Dependency injection initializer
    init(loader: OptimizedBibleDataLoader, pageSize: CGSize) {
        self.loader = loader
        self.pageSize = pageSize
    }
    
    init(pageSize: CGSize) {
        self.loader = OptimizedBibleDataLoader()
        self.pageSize = pageSize
    }
    
    /// Update the page size and clean up incompatible history entries
    func updatePageSize(_ newSize: CGSize) {
        guard pageSize != newSize else { return }
        
        // Clean up incompatible entries instead of clearing all history
        historyService.cleanupIncompatibleEntries(
            pageSize: newSize,
            horizontalPadding: LayoutMetrics.horizontalPagePadding,
            verticalPadding: LayoutMetrics.verticalPagePadding
        )
        
        print("📐 FragmentedPageNavigationManager: Page size updated, incompatible entries cleaned")
    }
    
    /// Navigate to the next fragmented page
    func navigateToNextFragmentedPage(
        currentFragmentedPage: FragmentedPage?,
        fragmentPending: VerseFragment?,
        generateFragmentedPage: (VerseKey) async -> Void
    ) async -> Bool {
        guard let currentPage = currentFragmentedPage else {
            print("❌ FRAGMENTED NAVIGATION: No current page for next navigation")
            return false
        }
        
        // Priority 1: Use pending fragment if available
        if let pending = fragmentPending {
            let key = VerseKey(
                book: pending.reference.book,
                chapter: pending.reference.chapter,
                verse: pending.reference.verse
            )
            await generateFragmentedPage(key)
            return true
        }
        
        // Priority 2: Find next verse after current page's end
        guard let nextVerse = await findNextVerse(after: currentPage.endVerse) else {
            print("❌ FRAGMENTED NAVIGATION: No next verse found")
            return false
        }
        
        await generateFragmentedPage(nextVerse)
        return true
    }
    
    /// Navigate to the previous fragmented page using enhanced history
    func navigateToPreviousFragmentedPage(
        restoreFromHistory: (PageHistoryEntry) async -> Bool
    ) async -> Bool {
        // Block navigation if no history available
        guard historyService.canGoBackward else {
            print("❌ FRAGMENTED NAVIGATION: No reliable history available - at start of Bible")
            return false
        }
        
        // Get the previous page from history
        guard let historyEntry = historyService.goBackward() else {
            print("❌ FRAGMENTED NAVIGATION: Failed to get history entry")
            return false
        }
        
        print("📚 FRAGMENTED NAVIGATION: Using enhanced history entry")
        print("📚 ENTRY: \(historyEntry.debugDescription)")
        
        // Set flag to prevent adding this page to history again
        isNavigatingFromHistory = true
        defer { isNavigatingFromHistory = false }
        
        // Restore page from history entry using multiple strategies
        if await restoreFromHistory(historyEntry) {
            print("✅ FRAGMENTED NAVIGATION: Successfully restored page from history")
            return true
        } else {
            print("❌ FRAGMENTED NAVIGATION: Failed to restore from history")
            // Push the entry back since we failed to restore it
            historyService.pushPageBack(historyEntry)
            return false
        }
    }
    
    /// Add a fragmented page to history if not navigating from history
    func addFragmentedPageToHistory(
        _ page: FragmentedPage,
        characterOffset: Int? = nil,
        fragmentOffset: Int? = nil
    ) {
        // Only add to history if we're not navigating from history
        guard !isNavigatingFromHistory else {
            print("📚 FRAGMENTED NAVIGATION: Skipping history add - navigating from history")
            return
        }
        
        // Create comprehensive history entry
        let historyEntry = PageHistoryEntry.createFromFragmentedPage(
            page,
            pageSize: pageSize,
            horizontalPadding: LayoutMetrics.horizontalPagePadding,
            verticalPadding: LayoutMetrics.verticalPagePadding,
            characterOffset: characterOffset,
            fragmentOffset: fragmentOffset
        )
        
        historyService.pushFragmentedPage(page, pageSize: pageSize)
        
        print("📚 FRAGMENTED NAVIGATION: Added page to history")
        print("📚 ENTRY: \(historyEntry.debugDescription)")
    }
    
    /// Check if backward navigation is possible
    var canGoBackward: Bool {
        return historyService.canGoBackward
    }
    
    /// Check if forward navigation is possible
    var canGoForward: Bool {
        return historyService.canGoForward
    }
    
    /// Clear all history (called when major layout changes occur)
    func clearHistory() {
        historyService.clearHistory()
        print("📚 FRAGMENTED NAVIGATION: Cleared all history")
    }
    
    /// Get debug information about current navigation state
    func getDebugInfo() -> String {
        let historyDebug = historyService.getDebugInfo()
        return """
        📊 FRAGMENTED NAVIGATION DEBUG:
        Page size: \(pageSize)
        Can go backward: \(canGoBackward)
        Can go forward: \(canGoForward)
        Is navigating from history: \(isNavigatingFromHistory)
        \(historyDebug)
        """
    }
    
    // MARK: - Private Helper Methods
    
    /// Find the next verse after the given verse reference
    private func findNextVerse(after verseRef: VerseReference) async -> VerseKey? {
        let currentKey = VerseKey(
            book: verseRef.book,
            chapter: verseRef.chapter,
            verse: verseRef.verse
        )
        
        guard let chapter = await loader.loadChapterContent(book: currentKey.book, chapter: currentKey.chapter) else { return nil }
        
        // Find the current verse in the chapter's verse array
        if let currentIndex = chapter.verses.firstIndex(where: { $0.verse == currentKey.verse }) {
            // Check if there's a next verse in the same chapter
            let nextIndex = currentIndex + 1
            if nextIndex < chapter.verses.count {
                let nextVerse = chapter.verses[nextIndex]
                let result = VerseKey(book: currentKey.book, chapter: currentKey.chapter, verse: nextVerse.verse)
                print("🔍 FRAGMENTED findNextVerse: \(currentKey.description) → \(result.description) (same chapter)")
                return result
            }
        }
        
        // No more verses in current chapter, try next chapter
        guard let meta = await loader.metadata,
              let bookIndex = meta.books.firstIndex(where: { $0.name == currentKey.book }) else { return nil }
        
        // Try next chapter in same book
        if currentKey.chapter < meta.books[bookIndex].chapterCount {
            let result = VerseKey(book: currentKey.book, chapter: currentKey.chapter + 1, verse: 1)
            print("🔍 FRAGMENTED findNextVerse: \(currentKey.description) → \(result.description) (next chapter)")
            return result
        }
        
        // Try first chapter of next book
        guard bookIndex + 1 < meta.books.count else { return nil }
        let nextBook = meta.books[bookIndex + 1].name
        let result = VerseKey(book: nextBook, chapter: 1, verse: 1)
        print("🔍 FRAGMENTED findNextVerse: \(currentKey.description) → \(result.description) (next book)")
        return result
    }
}
