//
//  BibleService.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation

// MARK: - Bible Service Protocol

protocol BibleServiceProtocol: Actor {
    func getMetadata() async throws -> ImprovedBibleModels.BibleMetadata
    func loadChapter(book: String, chapter: Int) async throws -> ImprovedBibleModels.Chapter
    func searchBooks(query: String) async -> [ImprovedBibleModels.BookMetadata]
}

// MARK: - Bible Service Implementation

actor BibleService: BibleServiceProtocol {
    private let repository: BibleRepositoryProtocol
    private let cache: CacheServiceProtocol
    
    init(repository: BibleRepositoryProtocol, cache: CacheServiceProtocol) {
        self.repository = repository
        self.cache = cache
    }
    
    func getMetadata() async throws -> ImprovedBibleModels.BibleMetadata {
        let cacheKey = "bible_metadata"
        
        if let cached: ImprovedBibleModels.BibleMetadata = await cache.get(key: cacheKey) {
            return cached
        }
        
        let metadata = try await repository.loadMetadata()
        await cache.set(key: cacheKey, value: metadata)
        
        return metadata
    }
    
    func loadChapter(book: String, chapter: Int) async throws -> ImprovedBibleModels.Chapter {
        let cacheKey = "\(book):\(chapter)"
        
        if let cached: ImprovedBibleModels.Chapter = await cache.get(key: cacheKey) {
            return cached
        }
        
        let chapterData = try await repository.loadChapter(book: book, chapter: chapter)
        await cache.set(key: cacheKey, value: chapterData)
        
        return chapterData
    }
    
    func searchBooks(query: String) async -> [ImprovedBibleModels.BookMetadata] {
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
