//
//  UnifiedBibleModels.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation
import SwiftUI

// MARK: - Namespace to avoid conflicts
enum UnifiedBibleModels {
    
    // MARK: - Core Domain Models
    
    /// Core verse identifier - immutable value object
    struct VerseReference: Hashable, Codable, CustomStringConvertible {
        let book: String
        let chapter: Int
        let verse: Int
        
        var description: String { "\(book) \(chapter):\(verse)" }
        
        // Validation
        init?(book: String, chapter: Int, verse: Int) {
            guard !book.isEmpty, chapter > 0, verse > 0 else { return nil }
            self.book = book
            self.chapter = chapter
            self.verse = verse
        }
        
        // Unsafe initializer for known-good data
        init(unsafeBook: String, unsafeChapter: Int, unsafeVerse: Int) {
            self.book = unsafeBook
            self.chapter = unsafeChapter
            self.verse = unsafeVerse
        }
    }
    
    /// Represents a single verse with its content
    struct Verse: Hashable, Identifiable {
        let id = UUID()
        let reference: VerseReference
        let text: String
        
        init(reference: VerseReference, text: String) {
            self.reference = reference
            self.text = text
        }
    }
    
    /// Represents a chapter containing multiple verses
    struct Chapter: Hashable, Identifiable {
        let id = UUID()
        let book: String
        let number: Int
        let verses: [Verse]
        
        var verseCount: Int { verses.count }
        
        init(book: String, number: Int, verses: [Verse]) {
            self.book = book
            self.number = number
            self.verses = verses
        }
    }
    
    /// Represents a book containing multiple chapters
    struct Book: Hashable, Identifiable {
        let id = UUID()
        let name: String
        let chapters: [Chapter]
        
        var chapterCount: Int { chapters.count }
        
        init(name: String, chapters: [Chapter]) {
            self.name = name
            self.chapters = chapters
        }
    }
    
    /// Complete Bible structure
    struct Bible {
        let books: [Book]
        
        var bookCount: Int { books.count }
        
        func book(named name: String) -> Book? {
            books.first { $0.name == name }
        }
    }
    
    // MARK: - Presentation Models (View Layer)
    
    /// Lightweight metadata for UI display - Compatible with existing code
    struct BookMetadata: Hashable, Codable {
        let name: String
        let chapterCount: Int
        let abbreviation: String
        
        init(name: String, chapterCount: Int) {
            self.name = name
            self.chapterCount = chapterCount
            self.abbreviation = String(name.prefix(3))
        }
        
        enum CodingKeys: String, CodingKey {
            case name
            case chapterCount = "chapter_count"
            case abbreviation
        }
    }
    
    /// Collection of book metadata for navigation - Compatible with existing code
    struct BibleMetadata: Codable {
        let books: [BookMetadata]
        
        var oldTestamentBooks: [BookMetadata] {
            books.filter { BibleConstants.oldTestament.contains($0.name) }
        }
        
        var newTestamentBooks: [BookMetadata] {
            books.filter { BibleConstants.newTestament.contains($0.name) }
        }
    }
    
    // MARK: - Error Handling
    
    /// Result wrapper for service operations
    enum ServiceResult<T> {
        case success(T)
        case failure(BibleError)
        
        var value: T? {
            switch self {
            case .success(let value):
                return value
            case .failure:
                return nil
            }
        }
        
        var error: BibleError? {
            switch self {
            case .success:
                return nil
            case .failure(let error):
                return error
            }
        }
    }
    
    /// Comprehensive error handling for the app
    enum BibleError: LocalizedError, Equatable {
        case dataNotFound(String)
        case parsingError(String)
        case invalidInput(String)
        case networkError(String)
        case cacheError(String)
        
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
            case .cacheError(let detail):
                return "Cache error: \(detail)"
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
            case .cacheError:
                return "Clear app data and restart."
            }
        }
    }
    
    // MARK: - Navigation and Context
    
    /// Navigation context for better UX
    struct NavigationContext {
        let isFirstChapter: Bool
        let isLastChapter: Bool
        let isFirstVerse: Bool
        let isLastVerse: Bool
        let totalChapters: Int
        let totalVerses: Int
        
        init(currentChapter: Int, currentVerse: Int, totalChapters: Int, totalVerses: Int) {
            self.isFirstChapter = currentChapter == 1
            self.isLastChapter = currentChapter == totalChapters
            self.isFirstVerse = currentVerse == 1
            self.isLastVerse = currentVerse == totalVerses
            self.totalChapters = totalChapters
            self.totalVerses = totalVerses
        }
    }
    
    // MARK: - Constants
    
    enum BibleConstants {
        static let oldTestament: Set<String> = Set([
            "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua",
            "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles",
            "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
            "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations",
            "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah",
            "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi"
        ])
        
        static let newTestament: Set<String> = Set([
            "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians",
            "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians",
            "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus",
            "Philemon", "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John",
            "3 John", "Jude", "Revelation"
        ])
    }
}

// MARK: - Type Aliases for Backwards Compatibility
// These allow existing code to continue working while using the new unified models

enum UnifiedTypeAliases {
    typealias UnifiedBibleMetadata = UnifiedBibleModels.BibleMetadata
    typealias UnifiedBookMetadata = UnifiedBibleModels.BookMetadata
    typealias UnifiedChapter = UnifiedBibleModels.Chapter
    typealias UnifiedVerse = UnifiedBibleModels.Verse
    typealias UnifiedVerseReference = UnifiedBibleModels.VerseReference
    typealias UnifiedBibleError = UnifiedBibleModels.BibleError
    typealias UnifiedServiceResult<T> = UnifiedBibleModels.ServiceResult<T>
}
