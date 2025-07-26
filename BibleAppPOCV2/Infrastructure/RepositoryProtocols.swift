//
//  RepositoryProtocols.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation
import BibleAppPOCV2
import BibleAppPOCV2.Infrastructure.ServiceProtocols // If CacheServiceProtocol is here

// MARK: - Repository Protocols

protocol BibleRepositoryProtocol: Actor {
    func loadMetadata() async throws -> BibleMetadata
    func loadChapter(book: String, chapter: Int) async throws -> Chapter
// }

    func get<T>(key: String) async -> T?
    func set<T>(key: String, value: T) async
    func remove(key: String) async
    func clear() async
}

// MARK: - Generic Cache Implementation

actor GenericCacheService: CacheServiceProtocol {
    private var storage: [String: Any] = [:]
    private let maxSize: Int
    private var accessOrder: [String] = []
    
    init(maxSize: Int = 50) {
        self.maxSize = maxSize
    }
    
    func get<T>(key: String) async -> T? {
        // Update access order
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)
        
        return storage[key] as? T
    }
    
    func set<T>(key: String, value: T) async {
        storage[key] = value
        
        // Update access order
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)
        
        // Evict if necessary
        if accessOrder.count > maxSize {
            let oldestKey = accessOrder.removeFirst()
            storage.removeValue(forKey: oldestKey)
        }
    }
    
    func remove(key: String) async {
        storage.removeValue(forKey: key)
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
    }
    
    func clear() async {
        storage.removeAll()
        accessOrder.removeAll()
    }
}
