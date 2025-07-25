// filepath: BibleAppPOCV2/Models/LegacyBibleModels.swift
//
//  LegacyBibleModels.swift
//  BibleAppPOCV2
//
//  Created by Jeff Hedrick on 6/13/25.
//

import Foundation

enum Legacy {
    struct Bible: Codable {
        let books: [Book]
    }
    
    struct Book: Codable, Identifiable {
        let id = UUID()
        let name: String
        let chapters: [Chapter]
        
        enum CodingKeys: String, CodingKey {
            case name, chapters
        }
    }
    
    struct Chapter: Codable, Identifiable {
        let id = UUID()
        let chapter: Int
        let verses: [Verse]
        
        enum CodingKeys: String, CodingKey {
            case chapter, verses
        }
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
