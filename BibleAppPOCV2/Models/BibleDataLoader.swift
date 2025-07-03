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

class BibleDataLoader {
    static func loadBible(named fileName: String = "KJV.json") -> Result<Bible, BibleLoadError> {
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
            let bible = try decoder.decode(Bible.self, from: data)
            return .success(bible)
        } catch {
            return .failure(.decodingFailed(error))
        }
    }
}

// Ensure these match your existing models or provide compatible interfaces
struct Bible: Codable {
    let books: [Book]
}

struct Book: Codable {
    let name: String
    let chapters: [Chapter]
}

struct Chapter: Codable {
    let chapter: Int
    let verses: [Verse]
}

struct Verse: Codable {
    let verse: Int
    let text: String
}
