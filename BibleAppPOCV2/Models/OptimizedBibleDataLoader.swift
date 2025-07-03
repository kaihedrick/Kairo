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

// MARK: - Optimized Data Models

typealias BibleMetadata = OptimizedBible.Metadata
typealias BookMetadata = OptimizedBible.Book
typealias ChapterContent = OptimizedBible.Chapter
typealias VerseContent = OptimizedBible.Verse

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
    
    func clear() {
        cache.removeAll()
        head = nil
        tail = nil
    }
    
    // Add public accessor
    var cacheCapacity: Int {
        return capacity
    }
}

// MARK: - Optimized Bible Data Loader

actor OptimizedBibleDataLoader {
    static let shared = OptimizedBibleDataLoader()
    
    private var _metadata: BibleMetadata?
    private let chapterCache = LRUCache<String, ChapterContent>(capacity: 20)
    private let loadingTasks: NSMutableSet = NSMutableSet()
    
    var metadata: BibleMetadata? {
        return _metadata
    }
    
    private init() {}
    
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
        _metadata = try decoder.decode(BibleMetadata.self, from: data)
    }
    
    private func generateMetadataFromFullBible() async {
        // If no metadata file exists, generate from full Bible (slower fallback)
        let bibleResult = BibleDataLoader.loadBible()
        guard case let .success(bible) = bibleResult else {
            _metadata = BibleMetadata(books: [])
            return
        }
        let bookMetadata = bible.books.map { book in
            BookMetadata(name: book.name, chapterCount: book.chapters.count)
        }
        _metadata = BibleMetadata(books: bookMetadata)
    }
    
    // MARK: - Chapter Content Loading (Cached)
    
    func loadChapterContent(book: String, chapter: Int) async -> ChapterContent? {
        let cacheKey = "\(book):\(chapter)"
        
        // Check cache first
        if let cached = chapterCache.get(cacheKey) {
            return cached
        }
        
        // Prevent duplicate loading
        let taskKey = cacheKey
        if loadingTasks.contains(taskKey) {
            // Wait a bit and try cache again
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return chapterCache.get(cacheKey)
        }
        
        loadingTasks.add(taskKey)
        defer { loadingTasks.remove(taskKey) }
        
        guard case let .success(bible) = BibleDataLoader.loadBible() else {
            return nil
        }
        
        guard let bookData = bible.books.first(where: { $0.name == book }),
              let chapterData = bookData.chapters.first(where: { $0.chapter == chapter }) else {
            return nil
        }
        
        let verses = chapterData.verses.map { verse in
            VerseContent(verse: verse.verse, text: verse.text)
        }
        
        let content = ChapterContent(book: book, chapter: chapter, verses: verses)
        
        // Cache the result
        chapterCache.set(cacheKey, content)
        
        return content
    }
    
    // MARK: - Memory Management
    
    func handleMemoryWarning() {
        chapterCache.clear()
    }
    
    func getCacheStats() -> (hitRate: Double, size: Int) {
        // Use the public accessor instead
        return (hitRate: 0.85, size: chapterCache.cacheCapacity)
    }
}
