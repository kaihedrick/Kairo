// filepath: BibleAppPOCV2/ViewModels/OptimizedBibleViewModel.swift
//
//  OptimizedBibleViewModel.swift
//  AIStudyBiblePOC
//
//  Created by Performance Optimization on 6/13/25.
//

import Foundation
import SwiftUI

// MARK: - Performance Monitor Integration

// Use the shared PerformanceMonitor from Utilities folder

// MARK: - Optimized Bible View Model

@MainActor
class OptimizedBibleViewModel: ObservableObject {
    // Use database-backed models for better performance and data integrity
    @Published var metadata: DatabaseBibleMetadata?
    @Published var isInitializing = true
    @Published var initializationProgress: Double = 0.0
    @Published var errorMessage: String?

    // Database-backed repository for all data operations
    private let repository: DatabaseBibleRepository
    private let dataLoader: DatabaseBibleDataLoader

    init(repository: DatabaseBibleRepository = .shared) {
        self.repository = repository
        self.dataLoader = DatabaseBibleDataLoader(repository: repository)
        Task {
            await initializeData()
        }
    }
    
    private func initializeData() async {
        do {
            // Start with metadata loading
            initializationProgress = 0.1

            // Use database repository for metadata loading
            try await dataLoader.loadBibleMetadata()
            metadata = dataLoader.metadata

            initializationProgress = 0.8
            initializationProgress = 1.0

            // Small delay to show completion
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

            isInitializing = false

            #if DEBUG
            print("✅ OptimizedBibleViewModel: Database initialization complete")
            if let metadata = metadata {
                print("   - Loaded \(metadata.books.count) books")
                print("   - Old Testament: \(metadata.oldTestamentBooks.count) books")
                print("   - New Testament: \(metadata.newTestamentBooks.count) books")
            }
            #endif

        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
            isInitializing = false

            #if DEBUG
            print("❌ OptimizedBibleViewModel: Database initialization failed: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Improved Architecture Methods

    /// Improved initialization with better error handling
    func initializeDataImproved() async {
        do {
            // Start with metadata loading
            initializationProgress = 0.1

            // Use database loader for better performance
            try await dataLoader.loadBibleMetadata()
            initializationProgress = 0.8

            // Get metadata with better error handling
            guard let loadedMetadata = dataLoader.metadata else {
                throw ImprovedBibleError.dataNotFound("Bible metadata")
            }

            metadata = loadedMetadata
            initializationProgress = 1.0

            // Small delay to show completion
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

            isInitializing = false

        } catch {
            handleError(error)
            isInitializing = false
        }
    }

    /// Improved error handling
    private func handleError(_ error: Error) {
        if let bibleError = error as? ImprovedBibleError {
            errorMessage = bibleError.localizedDescription
        } else {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
        }
    }

    /// Search books with improved architecture
    func searchBooksImproved(query: String) async -> [DatabaseBookMetadata] {
        guard let metadata = metadata else { return [] }

        // Use better filtering with validation
        return metadata.books.filter { book in
            !book.name.isEmpty &&
            book.name.localizedCaseInsensitiveContains(query)
        }
    }

    /// Search books with case-insensitive filtering
    func searchBooks(query: String) -> [DatabaseBookMetadata] {
        guard let metadata = metadata else { return [] }

        if query.isEmpty {
            return metadata.books
        }

        return metadata.books.filter { book in
            book.name.localizedCaseInsensitiveContains(query) ||
            book.abbreviation.localizedCaseInsensitiveContains(query)
        }
    }

    /// Get books by testament
    func booksByTestament(_ testament: String) -> [DatabaseBookMetadata] {
        guard let metadata = metadata else { return [] }

        switch testament.lowercased() {
        case "all":
            return metadata.books
        case "old":
            return metadata.oldTestamentBooks
        case "new":
            return metadata.newTestamentBooks
        default:
            return metadata.books
        }
    }

    // MARK: - Improved Error Types

    enum ImprovedBibleError: LocalizedError {
        case dataNotFound(String)
        case parsingError(String)
        case invalidInput(String)
        
        var errorDescription: String? {
            switch self {
            case .dataNotFound(let item):
                return "Could not find \(item)"
            case .parsingError(let detail):
                return "Parsing failed: \(detail)"
            case .invalidInput(let detail):
                return "Invalid input: \(detail)"
            }
        }
    }

    func handleMemoryWarning() {
        dataLoader.clearCache()
    }

    func retryInitialization() {
        errorMessage = nil
        isInitializing = true
        initializationProgress = 0.0

        Task {
            await initializeData()
        }
    }

    // MARK: - Database-Specific Methods

    /// Check if database connection is available
    func isDatabaseAvailable() async -> Bool {
        return await dataLoader.isDatabaseAvailable()
    }

    /// Get database status information
    func getDatabaseStatus() async -> (available: Bool, error: Error?) {
        return await dataLoader.getDatabaseStatus()
    }

    /// Load a specific chapter content
    func loadChapter(book: String, chapter: Int) async -> DatabaseChapter? {
        let result = await dataLoader.loadChapter(book: book, chapter: chapter)
        switch result {
        case .success(let chapter):
            return chapter
        case .failure(let error):
            #if DEBUG
            print("❌ OptimizedBibleViewModel: Load chapter failed: \(error.localizedDescription)")
            #endif
            errorMessage = "Load chapter failed: \(error.localizedDescription)"
            return nil
        }
    }

    /// Search verses across the entire Bible
    func searchVerses(query: String) async -> [DatabaseVerse] {
        do {
            return try await dataLoader.searchVerses(searchText: query)
        } catch {
            #if DEBUG
            print("❌ OptimizedBibleViewModel: Search failed: \(error.localizedDescription)")
            #endif
            errorMessage = "Search failed: \(error.localizedDescription)"
            return []
        }
    }

    /// Get a specific verse by reference
    func getVerse(book: String, chapter: Int, verse: Int) async -> DatabaseVerse? {
        do {
            return try await dataLoader.getVerse(book: book, chapter: chapter, verse: verse)
        } catch {
            #if DEBUG
            print("❌ OptimizedBibleViewModel: Get verse failed: \(error.localizedDescription)")
            #endif
            errorMessage = "Failed to load verse: \(error.localizedDescription)"
            return nil
        }
    }

    /// Load complete book data
    func loadBook(named bookName: String) async -> DatabaseBook? {
        do {
            return try await dataLoader.loadBook(named: bookName)
        } catch {
            #if DEBUG
            print("❌ OptimizedBibleViewModel: Load book failed: \(error.localizedDescription)")
            #endif
            errorMessage = "Failed to load book: \(error.localizedDescription)"
            return nil
        }
    }
}