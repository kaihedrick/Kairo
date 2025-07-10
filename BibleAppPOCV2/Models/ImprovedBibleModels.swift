//
//  ImprovedBibleModels.swift
//  BibleAppPOCV2
//
//  Created by Architecture Review on 7/9/25.
//

import Foundation
import SwiftUI

// MARK: - Domain Models (Business Logic Layer)

/// Testament enumeration for filtering books
public enum Testament: String, CaseIterable {
    case all = "All"
    case old = "Old Testament"
    case new = "New Testament"
}

/// Core verse identifier - immutable value object
public struct VerseReference: Hashable, Codable, CustomStringConvertible {
    let book: String
    let chapter: Int
    let verse: Int
    
    public var description: String { "\(book) \(chapter):\(verse)" }
    
    // Validation
    public init?(book: String, chapter: Int, verse: Int) {
        guard !book.isEmpty, chapter > 0, verse > 0 else { return nil }
        self.book = book
        self.chapter = chapter
        self.verse = verse
    }
    
    // Unsafe initializer for known-good data
    public init(unsafeBook: String, unsafeChapter: Int, unsafeVerse: Int) {
        self.book = unsafeBook
        self.chapter = unsafeChapter
        self.verse = unsafeVerse
    }
}

/// Represents a single verse with its content
public struct Verse: Hashable, Identifiable {
    public let id = UUID()
    let reference: VerseReference
    let text: String
    
    public init(reference: VerseReference, text: String) {
        self.reference = reference
        self.text = text
    }
}

/// Represents a chapter containing multiple verses
public struct Chapter: Hashable, Identifiable {
    public let id = UUID()
    let book: String
    let number: Int
    let verses: [Verse]
    
    var verseCount: Int { verses.count }
    
    public init(book: String, number: Int, verses: [Verse]) {
        self.book = book
        self.number = number
        self.verses = verses
    }
}

/// Represents a book containing multiple chapters
public struct Book: Hashable, Identifiable {
    public let id = UUID()
    let name: String
    let chapters: [Chapter]
    
    var chapterCount: Int { chapters.count }
    
    public init(name: String, chapters: [Chapter]) {
        self.name = name
        self.chapters = chapters
    }
}

/// Complete Bible structure
public struct Bible {
    let books: [Book]
    
    var bookCount: Int { books.count }
    
    func book(named name: String) -> Book? {
        books.first { $0.name == name }
    }
}

// MARK: - Presentation Models (View Layer)

/// Lightweight metadata for UI display
public struct BookMetadata: Hashable, Codable {
    let name: String
    let chapterCount: Int
    let abbreviation: String
    
    public init(name: String, chapterCount: Int) {
        self.name = name
        self.chapterCount = chapterCount
        self.abbreviation = String(name.prefix(3))
    }
}

/// Collection of book metadata for navigation
public struct BibleMetadata: Codable {
    let books: [BookMetadata]
    
    var oldTestamentBooks: [BookMetadata] {
        books.filter { BibleConstants.oldTestament.contains($0.name) }
    }
    
    var newTestamentBooks: [BookMetadata] {
        books.filter { BibleConstants.newTestament.contains($0.name) }
    }
}

/// Page of formatted content for display
public struct PageContent: Identifiable, Equatable {
    public let id = UUID()
    let attributedText: AttributedString
    let startReference: VerseReference
    let endReference: VerseReference
    let references: [VerseReference]
    
    public static func == (lhs: PageContent, rhs: PageContent) -> Bool {
        lhs.id == rhs.id &&
        lhs.startReference == rhs.startReference &&
        lhs.endReference == rhs.endReference
    }
}

// MARK: - Constants

public enum BibleConstants {
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

// MARK: - Service Layer Types

/// Result wrapper for service operations
public enum ServiceResult<T> {
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
public enum BibleError: LocalizedError, Equatable {
    case dataNotFound(String)
    case parsingError(String)
    case invalidInput(String)
    case networkError(String)
    case cacheError(String)
    
    public var errorDescription: String? {
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
    
    public var recoverySuggestion: String? {
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

// MARK: - Advanced Domain Models

/// Represents a range of verses for pagination
public struct VerseRange: Hashable, Codable {
    let start: VerseReference
    let end: VerseReference
    
    public init?(start: VerseReference, end: VerseReference) {
        // Validate that end comes after start
        guard start.book == end.book else { return nil }
        guard start.chapter < end.chapter || 
              (start.chapter == end.chapter && start.verse <= end.verse) else { return nil }
        
        self.start = start
        self.end = end
    }
    
    var description: String {
        if start.chapter == end.chapter {
            if start.verse == end.verse {
                return start.description
            } else {
                return "\(start.book) \(start.chapter):\(start.verse)-\(end.verse)"
            }
        } else {
            return "\(start.description) - \(end.description)"
        }
    }
}

/// Navigation context for better UX
public struct NavigationContext {
    let isFirstChapter: Bool
    let isLastChapter: Bool
    let isFirstVerse: Bool
    let isLastVerse: Bool
    let totalChapters: Int
    let totalVerses: Int
    
    public init(currentChapter: Int, currentVerse: Int, totalChapters: Int, totalVerses: Int) {
        self.isFirstChapter = currentChapter == 1
        self.isLastChapter = currentChapter == totalChapters
        self.isFirstVerse = currentVerse == 1
        self.isLastVerse = currentVerse == totalVerses
        self.totalChapters = totalChapters
        self.totalVerses = totalVerses
    }
}


// MARK: - Namespaced Access for Migration Compatibility
/// Provides namespaced access to the improved models. This helps avoid
/// type name collisions while migrating legacy code. Each alias refers to
/// the corresponding top-level type defined in this file.
public enum ImprovedBibleModels {
    /// Sorted aliases for easier discovery and consistency
    public typealias Bible             = BibleAppPOCV2.Bible
    public typealias BibleConstants    = BibleAppPOCV2.BibleConstants
    public typealias BibleError        = BibleAppPOCV2.BibleError
    public typealias BibleMetadata     = BibleAppPOCV2.BibleMetadata
    public typealias Book              = BibleAppPOCV2.Book
    public typealias BookMetadata      = BibleAppPOCV2.BookMetadata
    public typealias Chapter           = BibleAppPOCV2.Chapter
    public typealias NavigationContext = BibleAppPOCV2.NavigationContext
    public typealias PageContent       = BibleAppPOCV2.PageContent
    public typealias ServiceResult<T>  = BibleAppPOCV2.ServiceResult<T>
    public typealias Verse             = BibleAppPOCV2.Verse
    public typealias VerseRange        = BibleAppPOCV2.VerseRange
    public typealias VerseReference    = BibleAppPOCV2.VerseReference
}
