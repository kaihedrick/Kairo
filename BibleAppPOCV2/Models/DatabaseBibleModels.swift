// filepath: BibleAppPOCV2/Models/DatabaseBibleModels.swift
import Foundation
import SwiftUI

// MARK: - Database-Backed Bible Models

/// Database-backed verse model that wraps SQLite data
public struct DatabaseVerse: Hashable, Identifiable, Codable {
    public let id: UUID
    public let databaseId: Int
    public let chapterId: Int
    public let book: String
    public let chapter: Int
    public let verseNumber: Int
    public let text: String

    /// Create from SQLite Verse data
    init(from verse: BibleDatabase.Verse, chapterId: Int, book: String, chapter: Int) {
        self.id = UUID()
        self.databaseId = verse.id
        self.chapterId = chapterId
        self.book = book
        self.chapter = chapter
        self.verseNumber = verse.verseNumber
        self.text = verse.text
    }

    /// Create from individual parameters
    init(book: String, chapter: Int, verseNumber: Int, text: String) {
        self.id = UUID()
        self.databaseId = -1 // Not from database, so use -1
        self.chapterId = -1  // Not from database, so use -1
        self.book = book
        self.chapter = chapter
        self.verseNumber = verseNumber
        self.text = text
    }

    /// Create a reference string for this verse
    func referenceString(bookName: String, chapterNumber: Int) -> String {
        return "\(bookName) \(chapterNumber):\(verseNumber)"
    }
}

/// Database-backed chapter model
public struct DatabaseChapter: Hashable, Identifiable {
    public let id: UUID
    public let databaseId: Int
    public let bookId: Int
    public let chapterNumber: Int
    public let name: String
    public let verses: [DatabaseVerse]

    /// Create from SQLite Chapter data and verses
    init(from chapter: BibleDatabase.Chapter, verses: [DatabaseVerse]) {
        self.id = UUID()
        self.databaseId = chapter.id
        self.bookId = chapter.bookId
        self.chapterNumber = chapter.chapterNumber
        self.name = chapter.name
        self.verses = verses
    }

    /// Create from individual parameters
    init(book: String, chapterNumber: Int, verses: [DatabaseVerse]) {
        self.id = UUID()
        self.databaseId = -1 // Not from database
        self.bookId = -1     // Not from database
        self.chapterNumber = chapterNumber
        self.name = "\(book) \(chapterNumber)"
        self.verses = verses
    }

    /// Get verse count
    var verseCount: Int {
        return verses.count
    }

    /// Get verse by number (1-based)
    func verseByNumber(_ number: Int) -> DatabaseVerse? {
        return verses.first { $0.verseNumber == number }
    }
}

/// Database-backed book model
public struct DatabaseBook: Hashable, Identifiable {
    public let id: UUID
    public let databaseId: Int
    public let name: String
    public let chapters: [DatabaseChapter]

    /// Create from SQLite Book data and chapters
    init(from book: BibleDatabase.Book, chapters: [DatabaseChapter]) {
        self.id = UUID()
        self.databaseId = book.id
        self.name = book.name
        self.chapters = chapters
    }

    var chapterCount: Int { chapters.count }
}

/// Database-backed complete Bible model
public struct DatabaseBible: Hashable, Identifiable {
    public let id: UUID
    public let books: [DatabaseBook]

    init(books: [DatabaseBook]) {
        self.id = UUID()
        self.books = books
    }

    func book(named name: String) -> DatabaseBook? {
        books.first { $0.name == name }
    }
}

// MARK: - Helper Extensions

extension DatabaseVerse {
    /// Check if this verse belongs to Old Testament
    func isOldTestament(bookName: String) -> Bool {
        let oldTestamentBooks = [
            "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
            "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
            "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
            "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
            "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
            "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel",
            "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk",
            "Zephaniah", "Haggai", "Zechariah", "Malachi"
        ]
        return oldTestamentBooks.contains(bookName)
    }

    /// Check if this verse belongs to New Testament
    func isNewTestament(bookName: String) -> Bool {
        let newTestamentBooks = [
            "Matthew", "Mark", "Luke", "John", "Acts", "Romans",
            "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
            "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
            "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews",
            "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John",
            "Jude", "Revelation"
        ]
        return newTestamentBooks.contains(bookName)
    }
}

extension DatabaseBible {
    /// Get all Old Testament books
    var oldTestamentBooks: [DatabaseBook] {
        books.filter { book in
            let oldTestamentBooks = [
                "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
                "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
                "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
                "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
                "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
                "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel",
                "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk",
                "Zephaniah", "Haggai", "Zechariah", "Malachi"
            ]
            return oldTestamentBooks.contains(book.name)
        }
    }

    /// Get all New Testament books
    var newTestamentBooks: [DatabaseBook] {
        books.filter { book in
            let newTestamentBooks = [
                "Matthew", "Mark", "Luke", "John", "Acts", "Romans",
                "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
                "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
                "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews",
                "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John",
                "Jude", "Revelation"
            ]
            return newTestamentBooks.contains(book.name)
        }
    }
}

// MARK: - Database Book Metadata

/// Lightweight metadata for books (database-backed)
public struct DatabaseBookMetadata: Hashable, Codable {
    let id: Int
    let name: String
    let chapterCount: Int
    let abbreviation: String

    init(from book: BibleDatabase.Book, chapterCount: Int) {
        self.id = book.id
        self.name = book.name
        self.chapterCount = chapterCount
        self.abbreviation = String(name.prefix(3))
    }
}

/// Complete Bible metadata (database-backed)
public struct DatabaseBibleMetadata: Codable {
    let books: [DatabaseBookMetadata]

    var oldTestamentBooks: [DatabaseBookMetadata] {
        books.filter { book in
            let oldTestamentBooks = [
                "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
                "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
                "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
                "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
                "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
                "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel",
                "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk",
                "Zephaniah", "Haggai", "Zechariah", "Malachi"
            ]
            return oldTestamentBooks.contains(book.name)
        }
    }

    var newTestamentBooks: [DatabaseBookMetadata] {
        books.filter { book in
            let newTestamentBooks = [
                "Matthew", "Mark", "Luke", "John", "Acts", "Romans",
                "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
                "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
                "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews",
                "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John",
                "Jude", "Revelation"
            ]
            return newTestamentBooks.contains(book.name)
        }
    }
}

// MARK: - Database Page Content

/// Database-backed page content with verses
public struct DatabasePageContent: Identifiable, Equatable, Codable {
    public let id: UUID
    public let content: AttributedString
    public let verses: [DatabaseVerse]
    public let verseKeys: [VerseKey]
    public let startVerse: VerseKey
    public let endVerse: VerseKey
    public let navigationContext: DatabaseNavigationContext
    public let startReference: String
    public let endReference: String
    public let references: [String]

    // Computed property for navigation title
    public var navTitle: String {
        if startVerse.book == endVerse.book && startVerse.chapter == endVerse.chapter {
            return "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse)-\(endVerse.verse)"
        } else if startVerse.book == endVerse.book && startVerse.chapter != endVerse.chapter {
            return "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse) - \(endVerse.chapter):\(endVerse.verse)"
        } else {
            return "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse) - \(endVerse.book) \(endVerse.chapter):\(endVerse.verse)"
        }
    }

    // Custom Codable implementation to handle AttributedString
    enum CodingKeys: String, CodingKey {
        case id, verses, verseKeys, startVerse, endVerse, navigationContext
        case startReference, endReference, references, contentString
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(verses, forKey: .verses)
        try container.encode(verseKeys, forKey: .verseKeys)
        try container.encode(startVerse, forKey: .startVerse)
        try container.encode(endVerse, forKey: .endVerse)
        try container.encode(navigationContext, forKey: .navigationContext)
        try container.encode(startReference, forKey: .startReference)
        try container.encode(endReference, forKey: .endReference)
        try container.encode(references, forKey: .references)
        try container.encode(String(content.characters), forKey: .contentString)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        verses = try container.decode([DatabaseVerse].self, forKey: .verses)
        verseKeys = try container.decode([VerseKey].self, forKey: .verseKeys)
        startVerse = try container.decode(VerseKey.self, forKey: .startVerse)
        endVerse = try container.decode(VerseKey.self, forKey: .endVerse)
        navigationContext = try container.decode(DatabaseNavigationContext.self, forKey: .navigationContext)
        startReference = try container.decode(String.self, forKey: .startReference)
        endReference = try container.decode(String.self, forKey: .endReference)
        references = try container.decode([String].self, forKey: .references)
        let contentString = try container.decode(String.self, forKey: .contentString)
        content = AttributedString(contentString)
    }

    public init(id: UUID = UUID(),
                content: AttributedString,
                verses: [DatabaseVerse],
                verseKeys: [VerseKey],
                startVerse: VerseKey,
                endVerse: VerseKey,
                navigationContext: DatabaseNavigationContext,
                startReference: String,
                endReference: String,
                references: [String]) {
        self.id = id
        self.content = content
        self.verses = verses
        self.verseKeys = verseKeys
        self.startVerse = startVerse
        self.endVerse = endVerse
        self.navigationContext = navigationContext
        self.startReference = startReference
        self.endReference = endReference
        self.references = references
    }

    public static func == (lhs: DatabasePageContent, rhs: DatabasePageContent) -> Bool {
        lhs.id == rhs.id &&
        lhs.startReference == rhs.startReference &&
        lhs.endReference == rhs.endReference
    }
}

// MARK: - Database Navigation Context

/// Navigation context for database-backed content
public struct DatabaseNavigationContext: Codable {
    let chapterNumber: Int
    let verseNumber: Int
    let totalChapters: Int
    let totalVerses: Int

    var isFirstChapter: Bool { chapterNumber == 1 }
    var isLastChapter: Bool { chapterNumber == totalChapters }
    var isFirstVerse: Bool { verseNumber == 1 }
    var isLastVerse: Bool { verseNumber == totalVerses }

    init(chapterNumber: Int, verseNumber: Int, totalChapters: Int, totalVerses: Int) {
        self.chapterNumber = chapterNumber
        self.verseNumber = verseNumber
        self.totalChapters = totalChapters
        self.totalVerses = totalVerses
    }
}
