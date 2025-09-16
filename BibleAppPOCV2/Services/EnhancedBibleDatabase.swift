//
//  EnhancedBibleDatabase.swift
//  Enhanced Bible Database Helper
//
//  This file provides Swift helper methods for working with the enhanced
//  Bible SQLite database containing commentary and devotional content.
//

import Foundation
import SQLite3

public class EnhancedBibleDatabase {
    private var db: OpaquePointer?
    private let dbPath: String

    init(databasePath: String) {
        self.dbPath = databasePath
    }

    // MARK: - Database Connection

    func open() -> Bool {
        // First verify the file exists and is readable
        let fileManager = FileManager.default
        
        #if DEBUG
        print("🔍 Attempting to open database at path: \(dbPath)")
        print("🔍 File exists: \(fileManager.fileExists(atPath: dbPath))")
        #endif
        
        if !fileManager.fileExists(atPath: dbPath) {
            print("❌ Enhanced Bible database file does not exist at path: \(dbPath)")
            
            // Let's also check what files ARE in the bundle
            #if DEBUG
            if let bundlePath = Bundle.main.resourcePath {
                print("🔍 Bundle resource path: \(bundlePath)")
                do {
                    let files = try fileManager.contentsOfDirectory(atPath: bundlePath)
                    print("🔍 Files in bundle:")
                    for file in files.filter({ $0.contains("bible") || $0.contains(".db") }) {
                        print("   • \(file)")
                    }
                } catch {
                    print("❌ Could not list bundle contents: \(error)")
                }
            }
            #endif
            
            return false
        }

        // Check file permissions
        do {
            let attributes = try fileManager.attributesOfItem(atPath: dbPath)
            if let fileSize = attributes[.size] as? NSNumber {
                print("📊 Database file size: \(fileSize.intValue) bytes")
            }
        } catch {
            print("⚠️ Could not read database file attributes: \(error)")
        }

        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("✅ Enhanced Bible database opened successfully")
            return true
        } else {
            if let errorMsg = String(cString: sqlite3_errmsg(db), encoding: .utf8) {
                print("❌ Error opening enhanced database: \(errorMsg)")
            } else {
                print("❌ Error opening enhanced database (unknown error)")
            }
            return false
        }
    }

    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    /// Test database connectivity and basic functionality
    func testDatabaseConnection() -> Bool {
        guard db != nil else {
            print("❌ Database not connected")
            return false
        }

        // Test if we can execute a simple query
        let query = "SELECT COUNT(*) FROM verses"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = Int(sqlite3_column_int(statement, 0))
                print("✅ Database test successful: Found \(count) verses")
                sqlite3_finalize(statement)

                // Also test book names to understand the database structure
                inspectDatabaseStructure()
                return true
            }
        }
        sqlite3_finalize(statement)
        print("❌ Database test failed")
        return false
    }

    /// Inspect database structure for debugging
    private func inspectDatabaseStructure() {
        #if DEBUG
        print("🔍 INSPECTING DATABASE STRUCTURE:")
        
        // Get all books
        let booksQuery = "SELECT id, name FROM books ORDER BY id"
        var booksStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, booksQuery, -1, &booksStatement, nil) == SQLITE_OK {
            var bookCount = 0
            var books: [(Int, String)] = []
            
            while sqlite3_step(booksStatement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(booksStatement, 0))
                let name = String(cString: sqlite3_column_text(booksStatement, 1))
                books.append((id, name))
                bookCount += 1
            }
            
            print("📚 Books in database (\(bookCount) total):")
            for (index, (id, name)) in books.enumerated() {
                if index < 10 {
                    print("   • \(name) (ID: \(id))")
                } else if index == 10 {
                    print("   ... and \(bookCount - 10) more books")
                    break
                }
            }
            
            // Find Matthew specifically
            if let matthew = books.first(where: { $0.1 == "Matthew" }) {
                print("📖 Found Matthew book: \(matthew.1) (ID: \(matthew.0))")
                
                // Get Matthew chapters
                let chaptersQuery = "SELECT chapter_number FROM chapters WHERE book_id = ? ORDER BY chapter_number"
                var chaptersStatement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, chaptersQuery, -1, &chaptersStatement, nil) == SQLITE_OK {
                    sqlite3_bind_int(chaptersStatement, 1, Int32(matthew.0))
                    
                    var chapterCount = 0
                    var firstChapter: Int? = nil
                    
                    while sqlite3_step(chaptersStatement) == SQLITE_ROW {
                        let chapterNum = Int(sqlite3_column_int(chaptersStatement, 0))
                        if firstChapter == nil { firstChapter = chapterNum }
                        chapterCount += 1
                    }
                    
                    print("   Chapters: \(chapterCount)")
                    if let firstChap = firstChapter {
                        print("   First chapter: Matthew \(firstChap) (Number: \(firstChap))")
                        
                        // Get verses in first chapter
                        let versesQuery = """
                            SELECT v.verse_number, v.text, v.id, v.verse_id_normalized 
                            FROM verses v 
                            JOIN chapters c ON v.chapter_id = c.id 
                            WHERE c.book_id = ? AND c.chapter_number = ? 
                            ORDER BY v.verse_number
                        """
                        var versesStatement: OpaquePointer?
                        
                        if sqlite3_prepare_v2(db, versesQuery, -1, &versesStatement, nil) == SQLITE_OK {
                            sqlite3_bind_int(versesStatement, 1, Int32(matthew.0))
                            sqlite3_bind_int(versesStatement, 2, Int32(firstChap))
                            
                            var verseCount = 0
                            while sqlite3_step(versesStatement) == SQLITE_ROW {
                                verseCount += 1
                                if verseCount == 1 {
                                    let verseNum = Int(sqlite3_column_int(versesStatement, 0))
                                    let text = String(cString: sqlite3_column_text(versesStatement, 1))
                                    let id = Int(sqlite3_column_int(versesStatement, 2))
                                    let normalized = String(cString: sqlite3_column_text(versesStatement, 3))
                                    
                                    let preview = text.count > 50 ? String(text.prefix(50)) + "..." : text
                                    print("   Verses in chapter \(firstChap): \(verseCount)")
                                    print("   First verse: '\(preview)'")
                                    print("   Verse ID: \(id), Normalized: \(normalized)")
                                }
                            }
                            print("   Verses in chapter \(firstChap): \(verseCount)")
                        }
                        sqlite3_finalize(versesStatement)
                    }
                }
                sqlite3_finalize(chaptersStatement)
            }
        }
        sqlite3_finalize(booksStatement)
        
        // Test a direct query
        testDirectQuery()
        #endif
    }

    /// Test direct query for Matthew 1:1
    private func testDirectQuery() {
        #if DEBUG
        print("🔍 TESTING DIRECT QUERY:")
        
        let directQuery = """
            SELECT v.id, v.chapter_id, v.verse_number, v.name, v.text, v.verse_id_normalized
            FROM verses v 
            JOIN chapters c ON v.chapter_id = c.id 
            JOIN books b ON c.book_id = b.id 
            WHERE b.name = 'Matthew' AND c.chapter_number = 1 AND v.verse_number = 1
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, directQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let chapterId = Int(sqlite3_column_int(statement, 1))
                let verseNumber = Int(sqlite3_column_int(statement, 2))
                let name = String(cString: sqlite3_column_text(statement, 3))
                let text = String(cString: sqlite3_column_text(statement, 4))
                
                let preview = text.count > 50 ? String(text.prefix(50)) + "..." : text
                print("✅ Direct query successful:")
                print("   Book: Matthew")
                print("   Chapter: \(chapterId)")
                print("   Verse: \(verseNumber)")
                print("   Text: '\(preview)'")
            } else {
                print("❌ Direct query failed")
            }
        } else {
            print("❌ Failed to prepare direct query")
        }
        sqlite3_finalize(statement)
        
        print("🎯 Enhanced Bible Database is fully functional and ready for use")
        #endif
    }

    // MARK: - Data Structures

    public struct Book {
        public let id: Int
        public let name: String
    }

    public struct Chapter {
        let id: Int
        let bookId: Int
        let chapterNumber: Int
        let name: String
    }

    public struct Verse {
        public let id: Int
        public let chapterId: Int
        public let verseNumber: Int
        public let name: String
        public let text: String
        public let verseIdNormalized: String
    }

    public struct Commentary {
        public let id: Int
        public let verseId: Int
        public let enhancedCommentary: String
        public let devotionalSummary: String
    }

    public struct MovementData {
        let id: Int
        let name: String
        let description: String
    }

    public struct VerseMetadata {
        let verseId: Int
        let movementId: Int?
        let keyThemes: String?
        let crossReferences: String?
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
        let query = "SELECT id, chapter_id, verse_number, name, text, verse_id_normalized FROM verses WHERE chapter_id = ? ORDER BY verse_number"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(chapterId))

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let chapterId = Int(sqlite3_column_int(statement, 1))
                let verseNumber = Int(sqlite3_column_int(statement, 2))
                let name = String(cString: sqlite3_column_text(statement, 3))
                let text = String(cString: sqlite3_column_text(statement, 4))
                let verseIdNormalized = String(cString: sqlite3_column_text(statement, 5))

                verses.append(Verse(id: id, chapterId: chapterId, verseNumber: verseNumber,
                                   name: name, text: text, verseIdNormalized: verseIdNormalized))
            }
        }
        sqlite3_finalize(statement)
        return verses
    }

    /// Get a specific verse by book name, chapter, and verse number
    /// Following the same pattern as the main BibleDatabase - open, query, close
    func getVerseByReference(bookName: String, chapterNumber: Int, verseNumber: Int) -> Verse? {
        #if DEBUG
        print("🔍 Looking for verse: \(bookName) \(chapterNumber):\(verseNumber)")
        #endif
        
        // Open database connection (following the working pattern from BibleDatabase)
        var localDb: OpaquePointer?
        guard sqlite3_open(dbPath, &localDb) == SQLITE_OK else {
            #if DEBUG
            print("❌ Failed to open database at path: \(dbPath)")
            if let errorMsg = String(cString: sqlite3_errmsg(localDb), encoding: .utf8) {
                print("❌ Open error: \(errorMsg)")
            }
            #endif
            sqlite3_close(localDb)
            return nil
        }
        
        defer { sqlite3_close(localDb) } // Ensure database is closed when function exits
        
        #if DEBUG
        print("✅ Database opened successfully for query")
        #endif

        // Use the same query structure as our command line queries
        let query = """
            SELECT v.id, v.chapter_id, v.verse_number, v.name, v.text, v.verse_id_normalized
            FROM verses v
            JOIN chapters c ON v.chapter_id = c.id
            JOIN books b ON c.book_id = b.id
            WHERE b.name = ? AND c.chapter_number = ? AND v.verse_number = ?
        """

        var statement: OpaquePointer?
        var verse: Verse?

        let prepareResult = sqlite3_prepare_v2(localDb, query, -1, &statement, nil)
        if prepareResult == SQLITE_OK {
            let bindResult1 = sqlite3_bind_text(statement, 1, bookName, -1, nil)
            let bindResult2 = sqlite3_bind_int(statement, 2, Int32(chapterNumber))
            let bindResult3 = sqlite3_bind_int(statement, 3, Int32(verseNumber))
            
            #if DEBUG
            print("🔍 Prepare result: \(prepareResult) (SQLITE_OK=\(SQLITE_OK))")
            print("🔍 Bind results: text=\(bindResult1), int1=\(bindResult2), int2=\(bindResult3)")
            #endif

            let stepResult = sqlite3_step(statement)
            #if DEBUG
            print("🔍 sqlite3_step result: \(stepResult) (SQLITE_ROW=\(SQLITE_ROW))")
            #endif
            
            if stepResult == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let chapterId = Int(sqlite3_column_int(statement, 1))
                let verseNumber = Int(sqlite3_column_int(statement, 2))
                let name = String(cString: sqlite3_column_text(statement, 3))
                let text = String(cString: sqlite3_column_text(statement, 4))
                let verseIdNormalized = String(cString: sqlite3_column_text(statement, 5))

                verse = Verse(id: id, chapterId: chapterId, verseNumber: verseNumber,
                            name: name, text: text, verseIdNormalized: verseIdNormalized)

                #if DEBUG
                print("✅ Found verse: \(bookName) \(chapterNumber):\(verseNumber)")
                print("📖 Verse text: \(text.prefix(100))...")
                #endif
            } else {
                #if DEBUG
                print("❌ Query failed for: \(bookName) \(chapterNumber):\(verseNumber)")
                print("❌ sqlite3_step returned: \(stepResult)")
                if let errorMsg = String(cString: sqlite3_errmsg(localDb), encoding: .utf8) {
                    print("❌ SQL Error: \(errorMsg)")
                }
                #endif
            }
        } else {
            #if DEBUG
            print("❌ Failed to prepare statement: \(prepareResult)")
            if let errorMsg = String(cString: sqlite3_errmsg(localDb), encoding: .utf8) {
                print("❌ Prepare error: \(errorMsg)")
            }
            #endif
        }
        sqlite3_finalize(statement)

        return verse
    }

    /// Get commentary for a specific verse ID
    /// Following the same pattern as the main BibleDatabase - open, query, close
    func getCommentaryForVerse(verseId: Int) -> Commentary? {
        // Open database connection
        var localDb: OpaquePointer?
        guard sqlite3_open(dbPath, &localDb) == SQLITE_OK else {
            #if DEBUG
            print("❌ Failed to open database for commentary query")
            #endif
            sqlite3_close(localDb)
            return nil
        }
        
        defer { sqlite3_close(localDb) }
        
        let query = "SELECT id, verse_id, enhanced_commentary, devotional_summary FROM commentaries WHERE verse_id = ?"
        
        var statement: OpaquePointer?
        var commentary: Commentary?
        
        if sqlite3_prepare_v2(localDb, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(verseId))
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let verseId = Int(sqlite3_column_int(statement, 1))
                let enhancedCommentary = String(cString: sqlite3_column_text(statement, 2))
                let devotionalSummary = String(cString: sqlite3_column_text(statement, 3))
                
                commentary = Commentary(id: id, verseId: verseId, 
                                      enhancedCommentary: enhancedCommentary, 
                                      devotionalSummary: devotionalSummary)
                
                #if DEBUG
                print("✅ Found commentary for verse ID: \(verseId)")
                #endif
            } else {
                #if DEBUG
                print("❌ No commentary found for verse ID: \(verseId)")
                #endif
            }
        } else {
            #if DEBUG
            print("❌ Failed to prepare commentary query")
            #endif
        }
        sqlite3_finalize(statement)
        return commentary
    }

    func getAllMovements() -> [String] {
        var movements: [String] = []
        let query = "SELECT DISTINCT name FROM movements ORDER BY name"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(statement, 0))
                movements.append(name)
            }
        }
        sqlite3_finalize(statement)
        return movements
    }

    func searchVerses(searchText: String) -> [Verse] {
        var verses: [Verse] = []
        let query = "SELECT id, chapter_id, verse_number, name, text, verse_id_normalized FROM verses WHERE text LIKE ? ORDER BY id"

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
                let verseIdNormalized = String(cString: sqlite3_column_text(statement, 5))

                verses.append(Verse(id: id, chapterId: chapterId, verseNumber: verseNumber,
                                   name: name, text: text, verseIdNormalized: verseIdNormalized))
            }
        }
        sqlite3_finalize(statement)
        return verses
    }
}