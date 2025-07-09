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
