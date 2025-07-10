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
    func searchBooksImproved(query: String) async -> [ImprovedBibleModels.BookMetadata] {
        guard let metadata = metadata else { return [] }
        
        return metadata.books.filter { book in
            book.name.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Legacy Adapter Pattern

/// Adapter to bridge existing OptimizedBibleDataLoader with new protocols
class LegacyBibleServiceAdapter: BibleServiceProtocol {

    func getMetadata() async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.BibleMetadata> {
        await OptimizedBibleDataLoader.shared.ensureMetadataLoaded()
        guard let metadata = await OptimizedBibleDataLoader.shared.metadata else {
            return .failure(.dataNotFound("Bible metadata"))
        }
        return .success(metadata)
    }

    func loadChapter(book: String, chapter: Int) async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.Chapter> {
        guard let chapterContent = await OptimizedBibleDataLoader.shared.loadChapterContent(book: book, chapter: chapter) else {
            return .failure(.dataNotFound("Chapter \(book) \(chapter)"))
        }
        
        // Convert existing data structures to new domain models
        let verses = chapterContent.verses.map { verseContent in
            let reference = ImprovedBibleModels.VerseReference(
                unsafeBook: book,
                unsafeChapter: chapter,
                unsafeVerse: verseContent.verse
            )
            return ImprovedBibleModels.Verse(reference: reference, text: verseContent.text)
        }
        let chapterModel = ImprovedBibleModels.Chapter(book: book, number: chapter, verses: verses)
        return .success(chapterModel)
    }

    func searchBooks(query: String) async -> [ImprovedBibleModels.BookMetadata] {
        let result = await getMetadata()
        switch result {
        case .success(let metadata):
            return metadata.books.filter { $0.name.localizedCaseInsensitiveContains(query) }
        case .failure:
            return []
        }
    }
}

// MARK: - Conversion Helpers

extension OptimizedPageSlice {
    
    /// Convert to new PageContent model
    func toPageContent() -> ImprovedBibleModels.PageContent {
        return ImprovedBibleModels.PageContent(
            attributedText: self.content,
            startReference: ImprovedBibleModels.VerseReference(
                unsafeBook: self.startVerse.book,
                unsafeChapter: self.startVerse.chapter,
                unsafeVerse: self.startVerse.verse
            ),
            endReference: ImprovedBibleModels.VerseReference(
                unsafeBook: self.endVerse.book,
                unsafeChapter: self.endVerse.chapter,
                unsafeVerse: self.endVerse.verse
            ),
            references: self.verseKeys.map { key in
                ImprovedBibleModels.VerseReference(
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
    var asVerseReference: ImprovedBibleModels.VerseReference {
        ImprovedBibleModels.VerseReference(
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
