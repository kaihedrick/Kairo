// filepath: BibleAppPOCV2/Services/PageCache.swift
import Foundation
// ...existing code...

/// ACID-Safe actor-based cache implementation with thread-safe operations
/// Provides Isolation guarantee through actor confinement
actor PageCache {
    // MARK: - Properties
    
    /// The internal cache storage
    private var cache: [String: PageNode] = [:]
    
    /// Maximum number of items to keep in cache
    private let maxCacheSize: Int
    
    /// Access order tracking for LRU eviction
    private var accessOrder: [String] = []
    
    // MARK: - Initialization
    
    init(maxSize: Int = 100) {
        self.maxCacheSize = maxSize
    }
    
    // MARK: - ACID-Safe Cache Operations
    
    /// Atomically retrieve a page from cache
    /// - Parameter key: The cache key to retrieve
    /// - Returns: The cached PageNode or nil if not found
    func get(key: String) -> PageNode? {
        guard let node = cache[key] else {
            return nil
        }
        
        // Update access order for LRU
        updateAccessOrder(for: key)
        return node
    }
    
    /// Atomically store a page in cache
    /// - Parameters:
    ///   - key: The cache key to store under
    ///   - node: The PageNode to store
    func set(key: String, node: PageNode) {
        // Store the node
        cache[key] = node
        
        // Update access order
        updateAccessOrder(for: key)
        
        // Ensure consistency by trimming if needed
        if cache.count > maxCacheSize {
            performLRUEviction()
        }
    }
    
    /// Atomically remove a page from cache
    /// - Parameter key: The cache key to remove
    func remove(key: String) {
        cache.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }
    
    /// Atomically clear all cached pages
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
    
    /// Get current cache size
    var count: Int {
        cache.count
    }
    
    /// Check if cache contains a key
    /// - Parameter key: The key to check
    /// - Returns: true if key exists in cache
    func contains(key: String) -> Bool {
        cache.keys.contains(key)
    }
    
    /// Get all cached keys
    var keys: [String] {
        Array(cache.keys)
    }
    
    // MARK: - ACID-Safe Trimming Operations
    
    /// Atomically trim cache to only keep allowed keys
    /// Provides Consistency guarantee by maintaining valid cache state
    /// - Parameter allowedKeys: Keys that should be kept in cache
    func trimToAllowedKeys(_ allowedKeys: Set<String>) {
        let keysToRemove = Set(cache.keys).subtracting(allowedKeys)
        
        // Remove keys atomically
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }
    
    /// Atomically trim cache to maximum of 3 pages
    /// Used for memory management in navigation scenarios
    func atomicTrimCacheToThreePages() {
        let maxPages = 3
        guard cache.count > maxPages else { return }
        
        // Keep the most recently accessed items
        let keysToKeep = Array(accessOrder.suffix(maxPages))
        let keysToRemove = Set(cache.keys).subtracting(Set(keysToKeep))
        
        // Remove excess keys atomically
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func updateAccessOrder(for key: String) {
        // Remove key from current position
        accessOrder.removeAll { $0 == key }
        
        // Add to end (most recently accessed)
        accessOrder.append(key)
    }
    
    private func performLRUEviction() {
        guard !accessOrder.isEmpty else { return }
        
        // Remove least recently used item
        let lruKey = accessOrder.removeFirst()
        cache.removeValue(forKey: lruKey)
    }
}

// MARK: - Cache Statistics Extension

extension PageCache {
    /// Get cache statistics for debugging
    func getStatistics() -> (count: Int, maxSize: Int, accessOrder: [String]) {
        return (cache.count, maxCacheSize, accessOrder)
    }
}
