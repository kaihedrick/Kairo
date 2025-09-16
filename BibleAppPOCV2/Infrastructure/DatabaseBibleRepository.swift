// filepath: BibleAppPOCV2/Infrastructure/DatabaseBibleRepository.swift
import Foundation

// MARK: - Database Bible Repository

/// Database-backed implementation of BibleRepositoryProtocol
/// Uses SQLite database through BibleDatabase class for all data operations
actor DatabaseBibleRepository: BibleRepositoryProtocol {

    // MARK: - Properties

    private let database: BibleDatabase
    private let databasePath: String

    // MARK: - Initialization

    init(databasePath: String = Bundle.main.path(forResource: "bible_kjv", ofType: "db") ?? "") {
        self.databasePath = databasePath
        self.database = BibleDatabase(databasePath: databasePath)
    }

    // MARK: - BibleRepositoryProtocol Implementation

    /// Load Bible metadata from database
    func loadMetadata() async throws -> DatabaseBibleMetadata {
        guard database.open() else {
            throw NSError(domain: "DatabaseBibleRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database connection failed"])
        }

        defer { database.close() }

        // Load all books from database
        let books = database.getAllBooks()

        // Convert to metadata with chapter counts
        let bookMetadata: [DatabaseBookMetadata] = books.map { book in
            let chapters = database.getChaptersForBook(bookId: book.id)
            return DatabaseBookMetadata(from: book, chapterCount: chapters.count)
        }

        return DatabaseBibleMetadata(books: bookMetadata)
    }

    /// Load a specific chapter from database
    func loadChapter(book: String, chapter: Int) async throws -> DatabaseChapter {
        guard database.open() else {
            throw NSError(domain: "DatabaseBibleRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database connection failed"])
        }

        defer { database.close() }

        // Find book by name
        let books = database.getAllBooks()
        guard let bookData = books.first(where: { $0.name.caseInsensitiveCompare(book) == .orderedSame }) else {
            throw NSError(domain: "DatabaseBibleRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Book '\(book)' not found"])
        }

        // Load chapters for this book
        let chapters = database.getChaptersForBook(bookId: bookData.id)
        guard let chapterData = chapters.first(where: { $0.chapterNumber == chapter }) else {
            throw NSError(domain: "DatabaseBibleRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chapter \(chapter) not found in book '\(book)'"])
        }

        // Load verses for this chapter
        let verses = database.getVersesForChapter(chapterId: chapterData.id)

        // Convert to database verse structures
        let databaseVerses: [DatabaseVerse] = verses.map { verse in
            DatabaseVerse(from: verse, chapterId: chapterData.id, book: book, chapter: chapter)
        }

        return DatabaseChapter(
            book: book,
            chapterNumber: chapter,
            verses: databaseVerses
        )
    }

    // MARK: - Additional Database Operations

    /// Load all books with their chapters (for complete Bible loading)
    func loadAllBooks() async throws -> [DatabaseBook] {
        guard database.open() else {
            throw NSError(domain: "DatabaseBibleRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database connection failed"])
        }

        defer { database.close() }

        let books = database.getAllBooks()
        var databaseBooks: [DatabaseBook] = []

        for book in books {
            let chapters = database.getChaptersForBook(bookId: book.id)
            var databaseChapters: [DatabaseChapter] = []

            for chapter in chapters {
                let verses = database.getVersesForChapter(chapterId: chapter.id)
                let databaseVerses = verses.map { DatabaseVerse(from: $0, chapterId: chapter.id, book: book.name, chapter: chapter.chapterNumber) }
                let databaseChapter = DatabaseChapter(from: chapter, verses: databaseVerses)
                databaseChapters.append(databaseChapter)
            }

            let databaseBook = DatabaseBook(from: book, chapters: databaseChapters)
            databaseBooks.append(databaseBook)
        }

        return databaseBooks
    }

    /// Search verses by text
    func searchVerses(searchText: String) async throws -> [DatabaseVerse] {
        guard database.open() else {
            throw NSError(domain: "DatabaseBibleRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database connection failed"])
        }

        defer { database.close() }

        let verses = database.searchVerses(searchText: searchText)

        // Convert to database verse structures (we need book/chapter context)
        var databaseVerses: [DatabaseVerse] = []

        // Load all books and chapters to get context
        let books = database.getAllBooks()

        for verse in verses {
            // Find the chapter that contains this verse
            for book in books {
                let chapters = database.getChaptersForBook(bookId: book.id)
                if let chapter = chapters.first(where: { $0.id == verse.chapterId }) {
                    let databaseVerse = DatabaseVerse(from: verse, chapterId: chapter.id, book: book.name, chapter: chapter.chapterNumber)
                    databaseVerses.append(databaseVerse)
                    break // Found the chapter, no need to search other books
                }
            }
        }

        return databaseVerses
    }

    /// Get verse by reference
    func getVerseByReference(book: String, chapter: Int, verse: Int) async throws -> DatabaseVerse? {
        guard database.open() else {
            throw NSError(domain: "DatabaseBibleRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database connection failed"])
        }

        defer { database.close() }

        guard let verseData = database.getVerseByReference(bookName: book, chapterNumber: chapter, verseNumber: verse) else {
            return nil
        }

        return DatabaseVerse(from: verseData, chapterId: -1, book: book, chapter: chapter)
    }

    /// Load book metadata (lightweight)
    func loadBookMetadata() async throws -> DatabaseBibleMetadata {
        guard database.open() else {
            throw NSError(domain: "DatabaseBibleRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database connection failed"])
        }

        defer { database.close() }

        let books = database.getAllBooks()
        let bookMetadata: [DatabaseBookMetadata] = books.map { book in
            let chapters = database.getChaptersForBook(bookId: book.id)
            return DatabaseBookMetadata(from: book, chapterCount: chapters.count)
        }

        return DatabaseBibleMetadata(books: bookMetadata)
    }

    // MARK: - Utility Methods

    /// Check if database connection is valid
    func isDatabaseAvailable() -> Bool {
        return database.open()
    }

    /// Close database connection
    func closeDatabase() {
        database.close()
    }
}

// MARK: - Singleton Instance

extension DatabaseBibleRepository {
    /// Shared instance for easy access throughout the app
    static let shared = DatabaseBibleRepository()
}
