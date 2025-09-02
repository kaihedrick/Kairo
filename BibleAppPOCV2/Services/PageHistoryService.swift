// filepath: BibleAppPOCV2/Services/PageHistoryService.swift
//
//  PageHistoryService.swift
//  BibleAppPOCV2
//
//  Created by refactoring from OnDemandPageGenerator.swift
//  Handles page history state and navigation using PageHistoryEntry objects
//

import Foundation
import SwiftUI

/// Manages page history for backward/forward navigation using PageHistoryEntry objects
final class PageHistoryService: ObservableObject {
    private let enhancedHistoryManager = EnhancedPageHistoryManager()
    
    /// Whether backward navigation is possible
    var canGoBackward: Bool {
        return enhancedHistoryManager.canGoBackward
    }
    
    /// Whether forward navigation is possible
    var canGoForward: Bool {
        return enhancedHistoryManager.canGoForward
    }
    
    /// Total number of pages in history
    var historyCount: Int {
        return enhancedHistoryManager.historyCount
    }
    
    /// Push a new page to history
    func pushPage(slice: OptimizedPageSlice, pageSize: CGSize) {
        let historyEntry = createHistoryEntryForLegacyPage(slice, pageSize: pageSize)
        enhancedHistoryManager.pushPage(historyEntry)
    }
    
    /// Push a fragmented page to history
    func pushOptimizedPage(_ optimizedPage: OptimizedPageSlice, pageSize: CGSize) {
        let historyEntry = createHistoryEntry(for: optimizedPage, pageSize: pageSize)
        enhancedHistoryManager.pushPage(historyEntry)
    }
    
    /// Navigate backward in history
    func goBackward() -> PageHistoryEntry? {
        return enhancedHistoryManager.goBackward()
    }
    
    /// Navigate forward in history
    func goForward() -> PageHistoryEntry? {
        return enhancedHistoryManager.goForward()
    }
    
    /// Push a page back to history (used when restoration fails)
    func pushPageBack(_ entry: PageHistoryEntry) {
        enhancedHistoryManager.pushPageBack(entry)
    }
    
    /// Clear all history
    func clearHistory() {
        enhancedHistoryManager.clearHistory()
    }
    
    /// Get debug info about current history state
    func getDebugInfo() -> String {
        return enhancedHistoryManager.getDebugInfo()
    }
    
    /// Clean up incompatible entries when layout changes
    func cleanupIncompatibleEntries(pageSize: CGSize, horizontalPadding: CGFloat, verticalPadding: CGFloat) {
        enhancedHistoryManager.cleanupIncompatibleEntries(
            pageSize: pageSize,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }
    
    /// Create a history entry for a legacy page slice
    private func createHistoryEntryForLegacyPage(_ page: OptimizedPageSlice, pageSize: CGSize) -> PageHistoryEntry {
        let layoutHash = PageHistoryEntry.createLayoutHash(
            pageSize: pageSize,
            horizontalPadding: LayoutMetrics.horizontalPagePadding,
            verticalPadding: LayoutMetrics.verticalPagePadding
        )
        
        return PageHistoryEntry(
            book: page.startVerse.book,
            chapter: page.startVerse.chapter,
            verse: page.startVerse.verse,
            characterOffset: nil,
            fragmentOffset: nil,
            renderedContent: String(page.content.characters), // Convert AttributedString to String properly
            navTitle: "\(page.startVerse.book) \(page.startVerse.chapter)",
            pageSize: pageSize,
            layoutHash: layoutHash,
            serializedFragmentedPage: nil, // Legacy pages don't have fragments
            verseKeys: ["\(page.startVerse.book) \(page.startVerse.chapter):\(page.startVerse.verse)"],
            hasSplitVerses: false, // Legacy pages don't typically split verses
            endBook: page.endVerse.book,
            endChapter: page.endVerse.chapter,
            endVerse: page.endVerse.verse
        )
    }
    
    /// Create a history entry for the current fragmented page
    private func createHistoryEntry(for optimizedPage: OptimizedPageSlice, pageSize: CGSize) -> PageHistoryEntry {
        return PageHistoryEntry.createFromOptimizedPage(
            optimizedPage,
            pageSize: pageSize,
            horizontalPadding: LayoutMetrics.horizontalPagePadding,
            verticalPadding: LayoutMetrics.verticalPagePadding,
            characterOffset: 0, // TODO: Add character offset tracking if needed
            fragmentOffset: 0   // TODO: Add fragment offset tracking if needed
        )
    }
}
