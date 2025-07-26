//
//  OptimizedBibleRepository.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation

// MARK: - Repository Implementation using existing OptimizedBibleDataLoader

actor OptimizedBibleRepository: BibleRepositoryProtocol {
    private let dataLoader = OptimizedBibleDataLoader()
    
    func loadMetadata() async throws -> BibleMetadata {
        try await dataLoader.loadBibleMetadata()
        guard let existingMetadata = await dataLoader.metadata else {
            throw BibleError.dataNotFound("Bible metadata")
        }
        
        // Convert existing metadata to unified format
        let unifiedBooks = existingMetadata.books.map { book in
            BookMetadata(name: book.name, chapterCount: book.chapterCount)
        }

        return BibleMetadata(books: unifiedBooks)
    }

    func loadChapter(book: String, chapter: Int) async throws -> Chapter {
        guard let chapterContent = await dataLoader.loadChapterContent(book: book, chapter: chapter) else {
            throw BibleError.dataNotFound("Chapter \(book) \(chapter)")
        }
        
        // Convert from OptimizedBible.ChapterContent to our unified Chapter
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
}
