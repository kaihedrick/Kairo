//
//  BibleDataLoading.swift
//  BibleAppPOCV2
//
//  Created by Architecture Review on 7/9/25.
//

import Foundation
import SwiftUI

// MARK: - Protocol-Based Architecture

/// Protocol for Bible data loading operations
protocol BibleDataLoading: Actor {
    associatedtype Metadata
    associatedtype ChapterContent
    
    func getMetadata() async -> Metadata?
    func ensureMetadataLoaded() async
    func loadBibleMetadata() async throws
    func loadChapterContent(book: String, chapter: Int) async -> ChapterContent?
    func handleMemoryWarning() async
    func getCacheStats() async -> (hitRate: Double, size: Int)
}

/// Protocol for page generation operations
protocol PageGenerating: ObservableObject {
    associatedtype PageType
    
    var currentPage: PageType? { get }
    var isGenerating: Bool { get }
    var lastError: String? { get }
    
    func generatePage(startingAt verse: (book: String, chapter: Int, verse: Int)) async
    func generateNextPage() async
    func generatePreviousPage() async
    func updatePageSize(_ newSize: CGSize)
    func handleMemoryPressure()
}

/// Protocol for text formatting operations
protocol TextFormatting {
    static func formatVerse(
        book: String,
        chapter: Int,
        verse: Int,
        text: String,
        showChapterHeader: Bool,
        showBookTitle: Bool
    ) -> AttributedString
    
    static func measureText(
        _ text: AttributedString,
        containerSize: CGSize
    ) -> CGSize
}

/// Generic cache protocol for type-safe caching
protocol Caching {
    associatedtype Key: Hashable
    associatedtype Value
    
    func get(_ key: Key) -> Value?
    func set(_ key: Key, _ value: Value)
    func remove(_ key: Key)
    func clear()
}

/// Protocol for dependency injection container
protocol DependencyContainer {
    func resolve<T>(_ type: T.Type) -> T
    func register<T>(_ type: T.Type, factory: @escaping () -> T)
}
