// filepath: BibleAppPOCV2/Models/DatabaseBibleDataLoader.swift
import Foundation

// MARK: - Database Bible Data Loader

/// Database-backed Bible data loader that replaces JSON-based loading
/// Uses DatabaseBibleRepository for all data operations
@MainActor
class DatabaseBibleDataLoader: ObservableObject {

    // MARK: - Shared Instance

    static let shared = DatabaseBibleDataLoader()

    // MARK: - Properties

    private let repository: DatabaseBibleRepository
    private var _metadata: DatabaseBibleMetadata?

    @Published private(set) var bible: DatabaseBible?
    @Published private(set) var loadError: Error?

    // MARK: - Initialization

    init(repository: DatabaseBibleRepository = .shared) {
        self.repository = repository
    }

    // MARK: - Metadata Loading

    /// Load Bible metadata from database
    func loadBibleMetadata() async throws {
        guard _metadata == nil else { return }

        do {
            _metadata = try await repository.loadBookMetadata()
            loadError = nil

            #if DEBUG
            print("✅ DatabaseBibleDataLoader: Loaded metadata for \(_metadata?.books.count ?? 0) books")
            #endif
        } catch {
            loadError = error
            #if DEBUG
            print("❌ DatabaseBibleDataLoader: Failed to load metadata: \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    /// Get current metadata
    var metadata: DatabaseBibleMetadata? {
        return _metadata
    }

    // MARK: - Chapter Content Loading

    /// Load chapter content from database
    func loadChapter(book: String, chapter: Int) async -> ServiceResult<DatabaseChapter> {
        #if DEBUG
        print("🔍 DatabaseBibleDataLoader: Attempting to load \(book) \(chapter)")
        #endif

        do {
            // Load the chapter from database repository
            let chapterData = try await repository.loadChapter(book: book, chapter: chapter)

            #if DEBUG
            print("✅ DatabaseBibleDataLoader: Successfully loaded \(book) \(chapter) with \(chapterData.verses.count) verses")
            #endif

            return .success(chapterData)

        } catch {
            #if DEBUG
            print("❌ DatabaseBibleDataLoader: Error loading \(book) \(chapter): \(error.localizedDescription)")
            #endif
            loadError = error
            return .failure(error)
        }
    }

    // MARK: - Book Loading

    /// Load complete book data from database
    func loadBook(named bookName: String) async throws -> DatabaseBook? {
        let allBooks = try await repository.loadAllBooks()
        return allBooks.first { $0.name.caseInsensitiveCompare(bookName) == .orderedSame }
    }

    // MARK: - Search Functionality

    /// Search verses in database
    func searchVerses(searchText: String) async throws -> [DatabaseVerse] {
        return try await repository.searchVerses(searchText: searchText)
    }

    // MARK: - Verse Retrieval

    /// Get specific verse by reference
    func getVerse(book: String, chapter: Int, verse: Int) async throws -> DatabaseVerse? {
        return try await repository.getVerseByReference(book: book, chapter: chapter, verse: verse)
    }

    // MARK: - Complete Bible Loading

    /// Load complete Bible from database
    func loadCompleteBible() async throws -> DatabaseBible {
        let books = try await repository.loadAllBooks()
        let bible = DatabaseBible(books: books)

        await MainActor.run {
            self.bible = bible
        }

        return bible
    }

    // MARK: - Utility Methods

    /// Check if database is available
    func isDatabaseAvailable() async -> Bool {
        return await repository.isDatabaseAvailable()
    }

    /// Clear any cached data
    func clearCache() {
        _metadata = nil
        bible = nil
        loadError = nil
    }

    /// Get database connection status
    func getDatabaseStatus() async -> (available: Bool, error: Error?) {
        let available = await repository.isDatabaseAvailable()
        return (available: available, error: loadError)
    }
}

