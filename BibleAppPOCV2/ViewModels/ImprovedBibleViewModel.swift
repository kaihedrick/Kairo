//
//  ImprovedBibleViewModel.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation
import SwiftUI

// Note: This ViewModel uses your existing architecture (OptimizedBibleDataLoader)
// but with improved error handling, validation, and structure.
// This demonstrates how to incrementally improve code without breaking changes.

// MARK: - Improved Error Handling

enum ImprovedBibleError: LocalizedError, Equatable {
    case dataNotFound(String)
    case parsingError(String)
    case invalidInput(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .dataNotFound(let item):
            return "Could not find \(item)"
        case .parsingError(let detail):
            return "Parsing failed: \(detail)"
        case .invalidInput(let detail):
            return "Invalid input: \(detail)"
        case .networkError(let detail):
            return "Network error: \(detail)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .dataNotFound:
            return "Please check your internet connection and try again."
        case .parsingError:
            return "The data format may be corrupted. Try restarting the app."
        case .invalidInput:
            return "Please check your input and try again."
        case .networkError:
            return "Check your internet connection."
        }
    }
}

// MARK: - Improved Bible View Model (Compatible with Existing Architecture)

@MainActor
final class ImprovedBibleViewModel: ObservableObject {
    @Published var metadata: OptimizedBibleModels.BibleMetadata?
    @Published var isInitializing = true
    @Published var initializationProgress: Double = 0.0
    @Published var lastError: ImprovedBibleError?
    @Published var isLoading = false
    
    // Use existing data loader for now (can be replaced with DI later)
    private let dataLoader = OptimizedBibleDataLoader.shared
    
    init() {
        Task {
            await initializeDataImproved()
        }
    }
    
    
    // MARK: - Improved Initialization with Better Error Handling
    
    func initializeDataImproved() async {
        isInitializing = true
        lastError = nil
        initializationProgress = 0.0
        
        do {
            initializationProgress = 0.2
            
            // Ensure metadata is loaded
            await dataLoader.ensureMetadataLoaded()
            initializationProgress = 0.6
            
            // Get metadata with better error handling
            guard let loadedMetadata = dataLoader.metadata else {
                throw ImprovedBibleError.dataNotFound("Bible metadata")
            }
            
            metadata = loadedMetadata
            initializationProgress = 0.9
            
            // Validate metadata
            guard !loadedMetadata.books.isEmpty else {
                throw ImprovedBibleError.parsingError("No books found in metadata")
            }
            
            initializationProgress = 1.0
            
            // Brief delay to show completion
            try await Task.sleep(nanoseconds: 300_000_000)
            
            isInitializing = false
            
        } catch let error as ImprovedBibleError {
            lastError = error
            isInitializing = false
        } catch {
            lastError = .networkError(error.localizedDescription)
            isInitializing = false
        }
    }
    
    // MARK: - Improved Search with Validation
    
    func searchBooksImproved(query: String) async -> [OptimizedBibleModels.BookMetadata] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return metadata?.books ?? []
        }
        
        guard let metadata = metadata else {
            lastError = .dataNotFound("Bible metadata not loaded")
            return []
        }
        
        isLoading = true
        
        // Simulate search delay for better UX
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let results = metadata.books.filter { book in
            book.name.localizedCaseInsensitiveContains(query) ||
            book.name.prefix(3).localizedCaseInsensitiveContains(query)
        }
        
        isLoading = false
        return results
    }
    
    // MARK: - Chapter Loading with Improved Error Handling
    
    func loadChapterImproved(book: String, chapter: Int) async -> OptimizedBible.ChapterContent? {
        guard !book.isEmpty, chapter > 0 else {
            lastError = .invalidInput("Invalid book name or chapter number")
            return nil
        }
        
        isLoading = true
        
        let result = await dataLoader.loadChapterContent(book: book, chapter: chapter)
        
        if result == nil {
            lastError = .dataNotFound("Chapter \(book) \(chapter)")
        }
        
        isLoading = false
        return result
    }
    
    // MARK: - Public Methods
    
    func retryInitialization() {
        Task {
            await initializeDataImproved()
        }
    }
    
    func clearError() {
        lastError = nil
    }
    
    func handleMemoryWarning() {
        Task {
            await dataLoader.handleMemoryWarning()
        }
    }
    
    // MARK: - Computed Properties
    
    var hasError: Bool {
        lastError != nil
    }
    
    var errorMessage: String {
        lastError?.localizedDescription ?? ""
    }
    
    var errorRecoverySuggestion: String {
        lastError?.recoverySuggestion ?? ""
    }
    
    var oldTestamentBooks: [OptimizedBibleModels.BookMetadata] {
        guard let metadata = metadata else { return [] }
        
        // Use your existing testament classification logic
        let oldTestamentSet = Set([
            "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua",
            "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles",
            "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
            "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations",
            "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah",
            "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi"
        ])
        
        return metadata.books.filter { book in
            oldTestamentSet.contains(book.name)
        }
    }
    
    var newTestamentBooks: [OptimizedBibleModels.BookMetadata] {
        guard let metadata = metadata else { return [] }
        
        let newTestamentSet = Set([
            "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians",
            "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians",
            "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus",
            "Philemon", "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John",
            "3 John", "Jude", "Revelation"
        ])
        
        return metadata.books.filter { book in
            newTestamentSet.contains(book.name)
        }
    }
}

// MARK: - Improved Chapter View Model

@MainActor
final class ImprovedChapterViewModel: ObservableObject {
    @Published var chapterContent: OptimizedBible.ChapterContent?
    @Published var isLoading = true
    @Published var lastError: ImprovedBibleError?
    
    let bookName: String
    let chapterNumber: Int
    
    private let dataLoader = OptimizedBibleDataLoader.shared
    
    init(bookName: String, chapterNumber: Int) {
        self.bookName = bookName
        self.chapterNumber = chapterNumber
    }
    
    func loadChapter() async {
        guard !bookName.isEmpty, chapterNumber > 0 else {
            lastError = .invalidInput("Invalid book name or chapter number")
            return
        }
        
        isLoading = true
        lastError = nil
        
        do {
            let content = await dataLoader.loadChapterContent(book: bookName, chapter: chapterNumber)
            
            if let content = content {
                // Validate content
                guard !content.verses.isEmpty else {
                    throw ImprovedBibleError.parsingError("Chapter contains no verses")
                }
                
                chapterContent = content
            } else {
                throw ImprovedBibleError.dataNotFound("Chapter \(bookName) \(chapterNumber)")
            }
            
        } catch let error as ImprovedBibleError {
            lastError = error
        } catch {
            lastError = .networkError(error.localizedDescription)
        }
        
        isLoading = false
    }
    
    func retryLoading() {
        Task {
            await loadChapter()
        }
    }
    
    func clearError() {
        lastError = nil
    }
    
    // MARK: - Computed Properties
    
    var hasError: Bool {
        lastError != nil
    }
    
    var errorMessage: String {
        lastError?.localizedDescription ?? ""
    }
    
    var verseCount: Int {
        chapterContent?.verses.count ?? 0
    }
}
