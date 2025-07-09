//
//  MigrationHelpers.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation

// MARK: - Migration Extension for OptimizedBibleViewModel

extension OptimizedBibleViewModel {
    
    // MARK: - Migration to New Architecture
    
    /// Creates an improved bible service using existing infrastructure
    private func createBibleService() -> BibleServiceProtocol {
        // For now, return a wrapper around existing functionality
        return LegacyBibleServiceAdapter()
    }
    
    /// Search books with new architecture (demonstration)
    func searchBooksImproved(query: String) async -> [BookMetadata] {
        guard let metadata = metadata else { return [] }
        
        return metadata.books.filter { book in
            book.name.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Legacy Adapter Pattern

/// Adapter to bridge existing OptimizedBibleDataLoader with new protocols
class LegacyBibleServiceAdapter: BibleServiceProtocol {
    
    func getMetadata() async throws -> BibleMetadata {
        await OptimizedBibleDataLoader.shared.ensureMetadataLoaded()
        guard let metadata = await OptimizedBibleDataLoader.shared.metadata else {
            throw BibleError.dataNotFound("Bible metadata")
        }
        return metadata
    }
    
    func loadChapter(book: String, chapter: Int) async throws -> Chapter {
        guard let chapterContent = await OptimizedBibleDataLoader.shared.loadChapterContent(book: book, chapter: chapter) else {
            throw BibleError.dataNotFound("Chapter \(book) \(chapter)")
        }
        
        // Convert existing data structures to new domain models
        let verses = chapterContent.verses.map { verseContent in
            let reference = VerseReference(
                unsafeBook: book,
                unsafeChapter: chapter,
                unsafeVerse: verseContent.verse
            )
            return Verse(reference: reference, text: verseContent.text)
        }
        
        return Chapter(book: book, number: chapter, verses: verses)
    }
    
    func searchBooks(query: String) async -> [BookMetadata] {
        do {
            let metadata = try await getMetadata()
            return metadata.books.filter { 
                $0.name.localizedCaseInsensitiveContains(query) 
            }
        } catch {
            return []
        }
    }
}

// MARK: - Conversion Helpers

extension OptimizedPageSlice {
    
    /// Convert to new PageContent model
    func toPageContent() -> PageContent {
        return PageContent(
            attributedText: self.content,
            startReference: VerseReference(
                unsafeBook: self.startVerse.book,
                unsafeChapter: self.startVerse.chapter,
                unsafeVerse: self.startVerse.verse
            ),
            endReference: VerseReference(
                unsafeBook: self.endVerse.book,
                unsafeChapter: self.endVerse.chapter,
                unsafeVerse: self.endVerse.verse
            ),
            references: self.verseKeys.map { key in
                VerseReference(
                    unsafeBook: key.book,
                    unsafeChapter: key.chapter,
                    unsafeVerse: key.verse
                )
            }
        )
    }
}

extension VerseKey {
    
    /// Convert to new VerseReference
    var asVerseReference: VerseReference {
        VerseReference(
            unsafeBook: self.book,
            unsafeChapter: self.chapter,
            unsafeVerse: self.verse
        )
    }
}

extension VerseReference {
    
    /// Convert to legacy VerseKey for compatibility
    var asVerseKey: VerseKey {
        VerseKey(book: self.book, chapter: self.chapter, verse: self.verse)
    }
}
