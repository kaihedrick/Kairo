//
//  SimpleBibleService.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation
import SwiftUI

// MARK: - Simple Service Protocol Using Existing Types

/// A simplified service that works with existing types
protocol SimpleBibleServiceProtocol {
    func getMetadata() async -> ImprovedBibleModels.BibleMetadata?
    func loadChapter(book: String, chapter: Int) async -> OptimizedBible.ChapterContent?
    func searchBooks(query: String) async -> [ImprovedBibleModels.BookMetadata]
}

// MARK: - Implementation

actor SimpleBibleService: SimpleBibleServiceProtocol {
    private let dataLoader = OptimizedBibleDataLoader.shared
    
    func getMetadata() async -> ImprovedBibleModels.BibleMetadata? {
        await dataLoader.ensureMetadataLoaded()
        return await dataLoader.metadata
    }
    
    func loadChapter(book: String, chapter: Int) async -> OptimizedBible.ChapterContent? {
        return await dataLoader.loadChapterContent(book: book, chapter: chapter)
    }
    
    func searchBooks(query: String) async -> [ImprovedBibleModels.BookMetadata] {
        guard let metadata = await getMetadata() else { return [] }
        
        let lowercasedQuery = query.lowercased()
        return metadata.books.filter { book in
            book.name.lowercased().contains(lowercasedQuery)
        }
    }
}

// MARK: - Async Result Helper

enum AsyncResult<T> {
    case success(T)
    case failure(Error)
    
    var value: T? {
        switch self {
        case .success(let value): return value
        case .failure: return nil
        }
    }
}

// MARK: - Service Extensions for Better Error Handling

extension SimpleBibleService {
    func getMetadataWithResult() async -> AsyncResult<ImprovedBibleModels.BibleMetadata> {
        if let metadata = await getMetadata() {
            return .success(metadata)
        } else {
            return .failure(BibleServiceError.metadataNotFound)
        }
    }
    
    func loadChapterWithResult(book: String, chapter: Int) async -> AsyncResult<OptimizedBible.ChapterContent> {
        if let content = await loadChapter(book: book, chapter: chapter) {
            return .success(content)
        } else {
            return .failure(BibleServiceError.chapterNotFound(book: book, chapter: chapter))
        }
    }
}

// MARK: - Service Errors

enum BibleServiceError: LocalizedError {
    case metadataNotFound
    case chapterNotFound(book: String, chapter: Int)
    case verseNotFound(book: String, chapter: Int, verse: Int)
    
    var errorDescription: String? {
        switch self {
        case .metadataNotFound:
            return "Bible metadata could not be loaded"
        case .chapterNotFound(let book, let chapter):
            return "Chapter \(chapter) of \(book) could not be found"
        case .verseNotFound(let book, let chapter, let verse):
            return "Verse \(verse) in \(book) \(chapter) could not be found"
        }
    }
}
