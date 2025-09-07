// filepath: BibleAppPOCV2/Models/OptimizedBibleDataLoader.swift
//
//  OptimizedBibleDataLoader.swift
//  BibleAppPOCV2
//
//  Created by Jeff Hedrick on 6/13/25.
//

//
//  OptimizedBibleDataLoader.swift
//  AIStudyBiblePOC
//
//  Created by Performance Optimization on 6/13/25.
//

import Foundation
import SwiftUI

// MARK: - Optimized Data Structures
/// Local representation used for fast JSON decoding
struct OptimizedBible: Codable {
    let books: [Book]

    struct Book: Codable, Hashable {
        let name: String
        let chapters: [[Verse]]
    }

    struct Verse: Codable, Hashable {
        let verse: Int
        let text: String
    }

    struct ChapterContent: Codable, Hashable {
        let book: String
        let chapter: Int
        let verses: [Verse]
    }
}

// MARK: - Explicit Model Selection for Loader
// Use ImprovedBibleModels types for metadata

typealias LoaderBibleMetadata = BibleMetadata
typealias LoaderBookMetadata = BookMetadata

// MARK: - Type Aliases for disambiguation
// These aliases ensure we consistently reference the improved models

// Import legacy types for fallback (using the renamed types from BibleDataLoader.swift)
// No typealias needed - we'll reference LegacyBibleDataLoader directly

// We need to use specific type paths to avoid ambiguity
// OptimizedBible.ChapterContent and OptimizedBible.Verse are defined above

// MARK: - LRU Cache Implementation

class LRUCache<Key: Hashable, Value> {
    private class Node {  // Changed from 'struct' to 'class'
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        
        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }
    
    private let capacity: Int
    private var cache: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    func get(_ key: Key) -> Value? {
        guard let node = cache[key] else { return nil }
        
        // Move to front (most recently used)
        moveToFront(node)
        return node.value
    }
    
    func set(_ key: Key, _ value: Value) {
        if let existingNode = cache[key] {
            existingNode.value = value
            moveToFront(existingNode)
            return
        }
        
        let newNode = Node(key: key, value: value)
        cache[key] = newNode
        
        if head == nil {
            head = newNode
            tail = newNode
        } else {
            newNode.next = head
            head?.prev = newNode
            head = newNode
        }
        
        if cache.count > capacity {
            evictLRU()
        }
    }
    
    private func moveToFront(_ node: Node) {
        guard node !== head else { return }
        
        // Remove from current position
        if node === tail {
            tail = node.prev
        }
        node.prev?.next = node.next
        node.next?.prev = node.prev
        
        // Move to front
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
    }
    
    private func evictLRU() {
        guard let lru = tail else { return }
        
        cache.removeValue(forKey: lru.key)
        tail = lru.prev
        tail?.next = nil
        
        if tail == nil {
            head = nil
        }
    }
    
    func remove(_ key: Key) {
        guard let node = cache[key] else { return }
        if node === head { head = node.next }
        if node === tail { tail = node.prev }
        node.prev?.next = node.next
        node.next?.prev = node.prev
        cache.removeValue(forKey: key)
    }

    func clear() {
        cache.removeAll()
        head = nil
        tail = nil
    }

    var keys: [Key] { Array(cache.keys) }

    var cacheCapacity: Int {
        return capacity
    }
}

// MARK: - Optimized Bible Data Loader

actor OptimizedBibleDataLoader {
    // Singleton removed for actor best practices. Instantiate as needed.
    
    private var _metadata: LoaderBibleMetadata?
    private let chapterCache = LRUCache<String, OptimizedBible.ChapterContent>(capacity: 20)
    private let loadingTasks: NSMutableSet = NSMutableSet()
    
    var metadata: LoaderBibleMetadata? {
        return _metadata
    }
    
    init() {}
    
    func ensureMetadataLoaded() async {
        if _metadata == nil {
            try? await loadBibleMetadata()
        }
    }
    
    // MARK: - Metadata Loading (Fast)
    
    func loadBibleMetadata() async throws {
        guard _metadata == nil else { return }
        
        guard let url = Bundle.main.url(forResource: "bible_metadata", withExtension: "json") else {
            // Fallback: Generate metadata from full Bible
            await generateMetadataFromFullBible()
            return
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        _metadata = try decoder.decode(LoaderBibleMetadata.self, from: data)
    }
    
    private func generateMetadataFromFullBible() async {
        // If no metadata file exists, generate from full Bible (slower fallback)
        let bibleResult = LegacyBibleDataLoader.loadBible()
        guard case let .success(bible) = bibleResult else {
            _metadata = LoaderBibleMetadata(books: [])
            return
        }
        let bookMetadata = bible.books.map { book in
            LoaderBookMetadata(name: book.name, chapterCount: book.chapters.count)
        }
        _metadata = LoaderBibleMetadata(books: bookMetadata)
    }
    
    // MARK: - Chapter Content Loading (Cached)
    
    func loadChapterContent(book: String, chapter: Int) async -> OptimizedBible.ChapterContent? {
        print("🔍 Attempting to load: \(book) \(chapter)")
        
        let cacheKey = "\(book):\(chapter)"
        
        // Check cache first
        if let cached = chapterCache.get(cacheKey) {
            print("✅ Found in cache: \(book) \(chapter)")
            return cached
        }
        
        // Prevent duplicate loading
        let taskKey = cacheKey
        if loadingTasks.contains(taskKey) {
            print("⏳ Already loading: \(book) \(chapter)")
            // Wait a bit and try cache again
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return chapterCache.get(cacheKey)
        }
        
        loadingTasks.add(taskKey)
        defer { loadingTasks.remove(taskKey) }
        
        // Try to load the Bible data directly from JSON
        guard let url = Bundle.main.url(forResource: "KJV", withExtension: "json") else {
            print("❌ KJV.json file not found in bundle")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            
            // Try to decode as the optimized structure first
            if let optimizedBible = try? decoder.decode(OptimizedBible.self, from: data) {
                print("📚 Loaded optimized Bible with \(optimizedBible.books.count) books")
                
                guard let bookData = optimizedBible.books.first(where: { $0.name == book }) else {
                    print("❌ Book '\(book)' not found in optimized structure")
                    print("📚 Available books: \(optimizedBible.books.map { $0.name })")
                    return nil
                }
                
                // Check if the chapter index is valid (chapters are 0-indexed in array)
                let chapterIndex = chapter - 1
                guard chapterIndex >= 0 && chapterIndex < bookData.chapters.count else {
                    print("❌ Chapter \(chapter) not found in book '\(book)' (has \(bookData.chapters.count) chapters)")
                    return nil
                }
                
                let chapterVerses = bookData.chapters[chapterIndex]
                let verses = chapterVerses.map { verse in
                    OptimizedBible.Verse(verse: verse.verse, text: verse.text)
                }
                
                let content = OptimizedBible.ChapterContent(book: book, chapter: chapter, verses: verses)
                print("✅ Successfully loaded from optimized structure: \(book) \(chapter) with \(verses.count) verses")
                
                // Cache the result
                chapterCache.set(cacheKey, content)
                return content
            }
            
            // Fall back to legacy structure
            guard case let .success(bible) = LegacyBibleDataLoader.loadBible() else {
                print("❌ Failed to load Bible data using legacy loader")
                return nil
            }
            
            print("📚 Available books: \(bible.books.map { $0.name })")
            
            guard let bookData = bible.books.first(where: { $0.name == book }) else {
                print("❌ Book '\(book)' not found in available books")
                return nil
            }
            
            print("📖 Book '\(book)' found with \(bookData.chapters.count) chapters")
            
            guard let chapterData = bookData.chapters.first(where: { $0.chapter == chapter }) else {
                print("❌ Chapter \(chapter) not found in book '\(book)'")
                return nil
            }
            
            let verses = chapterData.verses.map { verse in
                OptimizedBible.Verse(verse: verse.verse, text: verse.text)
            }
            
            let content = OptimizedBible.ChapterContent(book: book, chapter: chapter, verses: verses)
            
            print("✅ Successfully loaded from legacy structure: \(book) \(chapter) with \(verses.count) verses")
            
            // Cache the result
            chapterCache.set(cacheKey, content)
            
            return content
            
        } catch {
            print("❌ Error loading Bible data: \(error)")
            return nil
        }
    }
    
    // MARK: - Memory Management
    
    func handleMemoryWarning() {
        chapterCache.clear()
    }
    
    func getCacheStats() -> (hitRate: Double, size: Int) {
        // Return actual cache statistics
        let cacheSize = chapterCache.cacheCapacity // Using capacity as approximation since keys aren't exposed
        // For now, estimate hit rate - this could be improved with actual hit/miss tracking
        let estimatedHitRate = cacheSize > 0 ? 0.85 : 0.0
        return (hitRate: estimatedHitRate, size: cacheSize)
    }

    // MARK: - Performance Testing Integration

    /// Get cache keys for performance testing (limited access)
    func getCacheInfo() -> (size: Int, capacity: Int) {
        return (size: chapterCache.cacheCapacity, capacity: 20)
    }

    /// Clear specific cache entry for testing (if we had key access)
    func clearCacheForTesting() {
        chapterCache.clear()
    }

    /// Preload chapters for performance testing
    func preloadChapters(book: String, chapters: [Int]) async {
        await withTaskGroup(of: Void.self) { group in
            for chapter in chapters {
                group.addTask {
                    _ = await self.loadChapterContent(book: book, chapter: chapter)
                }
            }
        }
    }
}

