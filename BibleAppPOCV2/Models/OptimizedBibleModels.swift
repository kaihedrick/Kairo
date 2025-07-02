//
//  OptimizedBibleModels.swift
//  BibleAppPOCV2
//
//  Created by Jeff Hedrick on 6/13/25.
//

import Foundation

// Create new file for optimized models

enum OptimizedBible {
    struct Metadata: Codable {
        let books: [Book]
    }
    
    struct Book: Codable, Hashable {
        let name: String
        let chapterCount: Int
        
        enum CodingKeys: String, CodingKey {
            case name
            case chapterCount = "chapter_count"
        }
    }
    
    struct Chapter: Codable {
        let book: String
        let chapter: Int
        let verses: [Verse]
    }
    
    struct Verse: Codable, Identifiable {
        let id = UUID()
        let verse: Int
        let text: String
        
        enum CodingKeys: String, CodingKey {
            case verse, text
        }
    }
}
