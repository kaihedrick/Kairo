//
//  OptimizedBibleRepository.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation

// MARK: - Repository Implementation using existing OptimizedBibleDataLoader

actor OptimizedBibleRepository: BibleRepositoryProtocol {
    private let dataLoader = OptimizedBibleDataLoader.shared
    
    func loadMetadata() async throws -> UnifiedBibleMetadata {
        try await dataLoader.loadBibleMetadata()
        guard let existingMetadata = dataLoader.metadata else {
            throw UnifiedBibleError.dataNotFound("Bible metadata")
        }
        
        // Convert existing metadata to unified format
        let unifiedBooks = existingMetadata.books.map { book in
            UnifiedBookMetadata(name: book.name, chapterCount: book.chapterCount)
        }
        
        return UnifiedBibleMetadata(books: unifiedBooks)
    }
    
    func loadChapter(book: String, chapter: Int) async throws -> UnifiedChapter {
        guard let chapterContent = await dataLoader.loadChapterContent(book: book, chapter: chapter) else {
            throw UnifiedBibleError.dataNotFound("Chapter \(book) \(chapter)")
        }
        
        // Convert from OptimizedBible.ChapterContent to our unified Chapter
        let verses = chapterContent.verses.map { verseContent in
            let reference = UnifiedVerseReference(
                unsafeBook: book,
                unsafeChapter: chapter,
                unsafeVerse: verseContent.verse
            )
            return UnifiedVerse(reference: reference, text: verseContent.text)
        }
        
        return UnifiedChapter(book: book, number: chapter, verses: verses)
    }
}
