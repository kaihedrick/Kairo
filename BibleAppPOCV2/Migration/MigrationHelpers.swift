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
}

// MARK: - Legacy Adapter Pattern

/// Adapter to bridge existing OptimizedBibleDataLoader with new protocols
actor LegacyBibleServiceAdapter: BibleServiceProtocol {

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

    func loadVerse(reference: ImprovedBibleModels.VerseReference) async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.Verse> {
        let chapterResult = await loadChapter(book: reference.book, chapter: reference.chapter)
        switch chapterResult {
        case .success(let chapter):
            if let verse = chapter.verses.first(where: { $0.reference.verse == reference.verse }) {
                return .success(verse)
            } else {
                return .failure(.dataNotFound("Verse \(reference)"))
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    func searchBooks(query: String) async -> ImprovedBibleModels.ServiceResult<[ImprovedBibleModels.BookMetadata]> {
        let result = await getMetadata()
        switch result {
        case .success(let metadata):
            let filteredBooks = metadata.books.filter { $0.name.localizedCaseInsensitiveContains(query) }
            return .success(filteredBooks)
        case .failure(let error):
            return .failure(error)
        }
    }

    func getNavigationContext(for reference: ImprovedBibleModels.VerseReference) async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.NavigationContext> {
        let metadataResult = await getMetadata()
        switch metadataResult {
        case .success(let metadata):
            guard let book = metadata.books.first(where: { $0.name == reference.book }) else {
                return .failure(.dataNotFound("Book \(reference.book)"))
            }
            
            // Get chapter content to determine total verses
            let chapterResult = await loadChapter(book: reference.book, chapter: reference.chapter)
            switch chapterResult {
            case .success(let chapter):
                let context = ImprovedBibleModels.NavigationContext(
                    currentChapter: reference.chapter,
                    currentVerse: reference.verse,
                    totalChapters: book.chapterCount,
                    totalVerses: chapter.verseCount
                )
                return .success(context)
            case .failure(let error):
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
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
