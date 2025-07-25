// filepath: BibleAppPOCV2/Models/BibleDataLoader.swift
//
//  BibleDataLoader.swift
//  BibleAppPOCV2
//
//  Created by Jeff Hedrick on 6/13/25.
//

import Foundation

// Legacy loader bridge for migration compatibility
enum BibleLoadError: Error {
    case fileNotFound
    case decodingFailed(Error)
}

class LegacyBibleDataLoader {
    static func loadBible(named fileName: String = "KJV.json") -> Result<LegacyBible, BibleLoadError> {
        // Allow loading future translations by passing a different filename
        let ns = fileName as NSString
        let name = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? "json" : ns.pathExtension

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            return .failure(.fileNotFound)
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let bible = try decoder.decode(LegacyBible.self, from: data)
            return .success(bible)
        } catch {
            return .failure(.decodingFailed(error))
        }
    }
}

// Legacy types with unique names to avoid conflicts with other model files
struct LegacyBible: Codable {
    let books: [LegacyBook]
}

struct LegacyBook: Codable {
    let name: String
    let chapters: [LegacyChapter]
}

struct LegacyChapter: Codable {
    let chapter: Int
    let verses: [LegacyVerse]
}

struct LegacyVerse: Codable {
    let verse: Int
    let text: String
}


// MARK: - Modern ML-Ready Loader

struct BibleBook: Codable {
    let name: String
    let chapters: [BibleChapter]
}

struct BibleChapter: Codable {
    let chapter: Int
    let verses: [BibleVerse]
}

struct BibleVerse: Codable {
    let verse: Int
    let text: String
}

struct Bible: Codable {
    let books: [BibleBook]
}

@MainActor
class OptimizedBibleDataLoader: ObservableObject {
    static let shared = OptimizedBibleDataLoader()

    @Published private(set) var bible: Bible?
    @Published private(set) var loadError: Error?

    private init() {
        Task { await loadBible() }
    }

    /// Loads the Bible from the main bundle (default: KJV.json)
    func loadBible(named fileName: String = "KJV.json") async {
        let ns = fileName as NSString
        let name = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? "json" : ns.pathExtension

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            await MainActor.run { self.loadError = BibleLoadError.fileNotFound }
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let bible = try decoder.decode(Bible.self, from: data)
            await MainActor.run {
                self.bible = bible
                self.loadError = nil
            }
        } catch {
            await MainActor.run { self.loadError = error }
        }
    }

    /// Async fetch for a specific book
    func loadBook(named bookName: String) async -> BibleBook? {
        if bible == nil { await loadBible() }
        return bible?.books.first { $0.name.caseInsensitiveCompare(bookName) == .orderedSame }
    }

    /// Async fetch for a specific chapter
    func loadChapterContent(book: String, chapter: Int) async -> BibleChapter? {
        guard let bookObj = await loadBook(named: book) else { return nil }
        return bookObj.chapters.first { $0.chapter == chapter }
    }

    /// Async fetch for a specific verse
    func loadVerse(book: String, chapter: Int, verse: Int) async -> BibleVerse? {
        guard let chapterObj = await loadChapterContent(book: book, chapter: chapter) else { return nil }
        return chapterObj.verses.first { $0.verse == verse }
    }
}
