//
//  BibleDatabase.swift
//  Bible Database Helper
//
//  This file provides Swift helper methods for working with the KJV Bible SQLite database.
//

import Foundation
import SQLite3

class BibleDatabase {
    private var db: OpaquePointer?
    private let dbPath: String

    init(databasePath: String) {
        self.dbPath = databasePath
    }

    // MARK: - Database Connection

    func open() -> Bool {
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("Database opened successfully")
            return true
        } else {
            print("Error opening database")
            return false
        }
    }

    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    // MARK: - Data Structures

    struct Book {
        let id: Int
        let name: String
    }

    struct Chapter {
        let id: Int
        let bookId: Int
        let chapterNumber: Int
        let name: String
    }

    struct Verse {
        let id: Int
        let chapterId: Int
        let verseNumber: Int
        let name: String
        let text: String
    }

    // MARK: - Query Methods

    func getAllBooks() -> [Book] {
        var books: [Book] = []
        let query = "SELECT id, name FROM books ORDER BY id"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))

                books.append(Book(id: id, name: name))
            }
        }
        sqlite3_finalize(statement)
        return books
    }

    func getChaptersForBook(bookId: Int) -> [Chapter] {
        var chapters: [Chapter] = []
        let query = "SELECT id, book_id, chapter_number, name FROM chapters WHERE book_id = ? ORDER BY chapter_number"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(bookId))

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let bookId = Int(sqlite3_column_int(statement, 1))
                let chapterNumber = Int(sqlite3_column_int(statement, 2))
                let name = String(cString: sqlite3_column_text(statement, 3))

                chapters.append(Chapter(id: id, bookId: bookId, chapterNumber: chapterNumber, name: name))
            }
        }
        sqlite3_finalize(statement)
        return chapters
    }

    func getVersesForChapter(chapterId: Int) -> [Verse] {
        var verses: [Verse] = []
        let query = "SELECT id, chapter_id, verse_number, name, text FROM verses WHERE chapter_id = ? ORDER BY verse_number"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(chapterId))

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let chapterId = Int(sqlite3_column_int(statement, 1))
                let verseNumber = Int(sqlite3_column_int(statement, 2))
                let name = String(cString: sqlite3_column_text(statement, 3))
                let text = String(cString: sqlite3_column_text(statement, 4))

                verses.append(Verse(id: id, chapterId: chapterId, verseNumber: verseNumber, name: name, text: text))
            }
        }
        sqlite3_finalize(statement)
        return verses
    }

    func searchVerses(searchText: String) -> [Verse] {
        var verses: [Verse] = []
        let query = "SELECT id, chapter_id, verse_number, name, text FROM verses WHERE text LIKE ? ORDER BY id"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            let searchPattern = "%\(searchText)%"
            sqlite3_bind_text(statement, 1, searchPattern, -1, nil)

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let chapterId = Int(sqlite3_column_int(statement, 1))
                let verseNumber = Int(sqlite3_column_int(statement, 2))
                let name = String(cString: sqlite3_column_text(statement, 3))
                let text = String(cString: sqlite3_column_text(statement, 4))

                verses.append(Verse(id: id, chapterId: chapterId, verseNumber: verseNumber, name: name, text: text))
            }
        }
        sqlite3_finalize(statement)
        return verses
    }

    func getVerseByReference(bookName: String, chapterNumber: Int, verseNumber: Int) -> Verse? {
        let query = """
            SELECT v.id, v.chapter_id, v.verse_number, v.name, v.text
            FROM verses v
            JOIN chapters c ON v.chapter_id = c.id
            JOIN books b ON c.book_id = b.id
            WHERE b.name = ? AND c.chapter_number = ? AND v.verse_number = ?
        """

        var statement: OpaquePointer?
        var verse: Verse?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bookName, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(chapterNumber))
            sqlite3_bind_int(statement, 3, Int32(verseNumber))

            if sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let chapterId = Int(sqlite3_column_int(statement, 1))
                let verseNumber = Int(sqlite3_column_int(statement, 2))
                let name = String(cString: sqlite3_column_text(statement, 3))
                let text = String(cString: sqlite3_column_text(statement, 4))

                verse = Verse(id: id, chapterId: chapterId, verseNumber: verseNumber, name: name, text: text)
            }
        }
        sqlite3_finalize(statement)
        return verse
    }
}
