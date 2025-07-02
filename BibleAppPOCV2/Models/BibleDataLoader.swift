//
//  BibleDataLoader.swift
//  BibleAppPOCV2
//
//  Created by Jeff Hedrick on 6/13/25.
//

import Foundation

// Legacy loader bridge for migration compatibility
class BibleDataLoader {
    static func loadBible() -> Bible {
        // Simple implementation for migration
        // Read from your existing bible.json or equivalent source
        guard let url = Bundle.main.url(forResource: "KJV", withExtension: "json") else {
            return Bible(books: []) // Return empty Bible on failure
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(Bible.self, from: data)
        } catch {
            print("Error loading Bible: \(error)")
            return Bible(books: [])
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
