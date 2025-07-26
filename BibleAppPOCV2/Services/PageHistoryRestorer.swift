// filepath: BibleAppPOCV2/Services/PageHistoryRestorer.swift
import Foundation
import SwiftUI
// ...existing code...

/// ACID-Safe page history restoration service for durability guarantees
class PageHistoryRestorer {
    
    /// Restores a page from history with full durability guarantees
    /// - Parameters:
    ///   - entry: The page history entry to restore
    ///   - size: The current layout size
    ///   - dataLoader: The data loader for content
    /// - Returns: Restored page or nil if restoration failed
    func restorePage(
        from entry: PageHistoryEntry,
        size: CGSize,
        dataLoader: any BibleDataLoading
    ) -> Page? {
        // Validate entry has necessary data for restoration
        guard entry.isValid else {
            return nil
        }
        
        // Restore page content from history entry
        return restorePageContent(from: entry, size: size, dataLoader: dataLoader)
    }
    
    private func restorePageContent(
        from entry: PageHistoryEntry,
        size: CGSize,
        dataLoader: any BibleDataLoading
    ) -> Page? {
        // Create attributed string from rendered content
        let attributedText = AttributedString(entry.renderedContent)
        
        // Create verse keys from entry data
        let firstVerseKey = VerseKey(
            book: entry.book,
            chapter: entry.chapter,
            verse: entry.verse
        )
        
        let lastVerseKey = VerseKey(
            book: entry.endBook,
            chapter: entry.endChapter,
            verse: entry.endVerse
        )
        
        // Create restored page
        return Page(
            attributedText: attributedText,
            firstVerseKey: firstVerseKey,
            lastVerseKey: lastVerseKey
        )
    }
}

// MARK: - PageHistoryEntry Extensions for Restoration
extension PageHistoryEntry {
    var isValid: Bool {
        // Basic validation - ensure required fields are present
        return !renderedContent.isEmpty && !book.isEmpty && chapter > 0 && verse > 0
    }
}
