//
//  OptimizedBibleModels.swift
//  BibleAppPOCV2
//
//  Created by Jeff Hedrick on 6/13/25.
//

import Foundation

// MARK: - Main Bible Data Structure

struct OptimizedBible: Codable {
    let books: [Book]
    
    struct Book: Codable, Hashable {
        let name: String
        let chapters: [[Verse]]
    }

    struct Verse: Codable, Hashable {
        let verse: Int
        let text: String
    }
}

// MARK: - Metadata Models

struct BibleMetadata: Codable {
    let books: [BookMetadata]
}

struct BookMetadata: Codable, Hashable {
    let name: String
    let chapterCount: Int
    
    enum CodingKeys: String, CodingKey {
        case name
        case chapterCount = "chapter_count"
    }
}

// MARK: - Chapter Content Models

extension OptimizedBible {
    struct ChapterContent: Codable, Hashable {
        let book: String
        let chapter: Int
        let verses: [Verse]
    }
}

// MARK: - Type Aliases

typealias VerseContent = OptimizedBible.Verse
