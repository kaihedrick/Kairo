//
//  WorkingImprovedViewModel.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation
import SwiftUI

// MARK: - Enhanced Error Handling

enum BibleViewModelError: LocalizedError, Equatable {
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

// MARK: - Enhanced Bible View Model Extension

extension OptimizedBibleViewModel {
    
    // MARK: - Improved Error Handling
    
    var enhancedError: BibleViewModelError? {
        get { 
            // Convert existing errorMessage to typed error
            if let errorMessage = errorMessage {
                if errorMessage.contains("metadata") {
                    return .dataNotFound("Bible metadata")
                } else if errorMessage.contains("parsing") || errorMessage.contains("decode") {
                    return .parsingError(errorMessage)
                } else if errorMessage.contains("network") || errorMessage.contains("connection") {
                    return .networkError(errorMessage)
                } else {
                    return .networkError(errorMessage)
                }
            }
            return nil
        }
        set {
            if let error = newValue {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = nil
            }
        }
    }
    
    // MARK: - Enhanced Initialization
    
    func initializeWithBetterErrorHandling() async {
        do {
            isInitializing = true
            errorMessage = nil
            initializationProgress = 0.0
            
            initializationProgress = 0.2
            
            // Use existing initialization but with better error handling
            await OptimizedBibleDataLoader.shared.ensureMetadataLoaded()
            initializationProgress = 0.6
            
            guard let loadedMetadata = await OptimizedBibleDataLoader.shared.metadata else {
                enhancedError = .dataNotFound("Bible metadata")
                isInitializing = false
                return
            }
            
            // Validate metadata
            guard !loadedMetadata.books.isEmpty else {
                enhancedError = .parsingError("No books found in metadata")
                isInitializing = false
                return
            }
            
            metadata = loadedMetadata
            initializationProgress = 0.9
            
            initializationProgress = 1.0
            
            // Brief completion delay
            try await Task.sleep(nanoseconds: 300_000_000)
            
            isInitializing = false
            
        } catch {
            enhancedError = .networkError(error.localizedDescription)
            isInitializing = false
        }
    }
    
    // MARK: - Enhanced Search
    
    func searchBooksWithValidation(query: String) -> [BookMetadata] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedQuery.isEmpty else {
            return metadata?.books ?? []
        }
        
        guard let metadata = metadata else {
            enhancedError = .dataNotFound("Bible metadata not loaded")
            return []
        }
        
        return metadata.books.filter { book in
            book.name.localizedCaseInsensitiveContains(trimmedQuery) ||
            String(book.name.prefix(3)).localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
    
    // MARK: - Enhanced Testament Filtering
    
    var oldTestamentBooksFiltered: [BookMetadata] {
        let oldTestamentNames = Set([
            "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua",
            "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles",
            "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
            "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations",
            "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah",
            "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi"
        ])
        
        return metadata?.books.filter { oldTestamentNames.contains($0.name) } ?? []
    }
    
    var newTestamentBooksFiltered: [BookMetadata] {
        let newTestamentNames = Set([
            "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians",
            "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians",
            "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus",
            "Philemon", "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John",
            "3 John", "Jude", "Revelation"
        ])
        
        return metadata?.books.filter { newTestamentNames.contains($0.name) } ?? []
    }
    
    // MARK: - Enhanced Public Methods
    
    func retryInitializationEnhanced() {
        Task {
            await initializeWithBetterErrorHandling()
        }
    }
    
    func clearEnhancedError() {
        enhancedError = nil
    }
    
    // MARK: - Computed Properties
    
    var hasEnhancedError: Bool {
        enhancedError != nil
    }
    
    var enhancedErrorMessage: String {
        enhancedError?.localizedDescription ?? ""
    }
    
    var enhancedErrorRecovery: String {
        enhancedError?.recoverySuggestion ?? ""
    }
}

// MARK: - Enhanced Chapter View Model

@MainActor
final class EnhancedChapterViewModel: ObservableObject {
    @Published var chapterContent: OptimizedBible.ChapterContent?
    @Published var isLoading = true
    @Published var error: BibleViewModelError?
    
    let bookName: String
    let chapterNumber: Int
    
    init(bookName: String, chapterNumber: Int) {
        self.bookName = bookName
        self.chapterNumber = chapterNumber
    }
    
    func loadChapter() async {
        guard !bookName.isEmpty, chapterNumber > 0 else {
            error = .invalidInput("Invalid book name or chapter number")
            return
        }
        
        isLoading = true
        error = nil
        
        let content = await OptimizedBibleDataLoader.shared.loadChapterContent(
            book: bookName, 
            chapter: chapterNumber
        )
        
        if let content = content {
            guard !content.verses.isEmpty else {
                error = .parsingError("Chapter contains no verses")
                isLoading = false
                return
            }
            chapterContent = content
        } else {
            error = .dataNotFound("Chapter \(bookName) \(chapterNumber)")
        }
        
        isLoading = false
    }
    
    func retry() {
        Task { await loadChapter() }
    }
    
    func clearError() {
        error = nil
    }
    
    var hasError: Bool { error != nil }
    var errorMessage: String { error?.localizedDescription ?? "" }
    var verseCount: Int { chapterContent?.verses.count ?? 0 }
}
