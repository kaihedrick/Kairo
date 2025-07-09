//
//  CleanBibleService.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation
import SwiftUI

// MARK: - Clean Service Using Only Existing Types

/// A clean service that works directly with existing OptimizedBible types
/// This avoids all naming conflicts and ambiguities
protocol CleanBibleServiceProtocol {
    func getMetadata() async -> OptimizedBibleModels.BibleMetadata?
    func loadChapter(book: String, chapter: Int) async -> OptimizedBible.ChapterContent?
    func searchBooks(query: String) async -> [OptimizedBibleModels.BookMetadata]
}

// MARK: - Implementation

actor CleanBibleService: CleanBibleServiceProtocol {
    private let dataLoader = OptimizedBibleDataLoader.shared
    
    func getMetadata() async -> OptimizedBibleModels.BibleMetadata? {
        await dataLoader.ensureMetadataLoaded()
        return dataLoader.metadata
    }
    
    func loadChapter(book: String, chapter: Int) async -> OptimizedBible.ChapterContent? {
        return await dataLoader.loadChapterContent(book: book, chapter: chapter)
    }
    
    func searchBooks(query: String) async -> [OptimizedBibleModels.BookMetadata] {
        guard let metadata = await getMetadata() else { return [] }
        
        let lowercasedQuery = query.lowercased()
        return metadata.books.filter { book in
            book.name.lowercased().contains(lowercasedQuery)
        }
    }
}

// MARK: - Result Helper for Error Handling

enum CleanServiceResult<T> {
    case success(T)
    case failure(CleanServiceError)
    
    var value: T? {
        switch self {
        case .success(let value): return value
        case .failure: return nil
        }
    }
    
    var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }
}

enum CleanServiceError: LocalizedError {
    case metadataNotFound
    case chapterNotFound(book: String, chapter: Int)
    case verseNotFound(book: String, chapter: Int, verse: Int)
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .metadataNotFound:
            return "Bible metadata could not be loaded"
        case .chapterNotFound(let book, let chapter):
            return "Chapter \(chapter) of \(book) could not be found"
        case .verseNotFound(let book, let chapter, let verse):
            return "Verse \(verse) in \(book) \(chapter) could not be found"
        case .networkError:
            return "Network connection error"
        }
    }
}

// MARK: - Extended Service with Result Types

extension CleanBibleService {
    func getMetadataWithResult() async -> CleanServiceResult<OptimizedBibleModels.BibleMetadata> {
        if let metadata = await getMetadata() {
            return .success(metadata)
        } else {
            return .failure(.metadataNotFound)
        }
    }
    
    func loadChapterWithResult(book: String, chapter: Int) async -> CleanServiceResult<OptimizedBible.ChapterContent> {
        if let content = await loadChapter(book: book, chapter: chapter) {
            return .success(content)
        } else {
            return .failure(.chapterNotFound(book: book, chapter: chapter))
        }
    }
}
