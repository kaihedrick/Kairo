import Foundation
import SwiftUI

struct FlattenedVerse {
    let book: String
    let chapter: Int
    let verse: Int
    let attributed: AttributedString
}

class BibleFormatter {
    
    static func flattenBible(bible: Legacy.Bible) -> [FlattenedVerse] {
        var result: [FlattenedVerse] = []
        
        for book in bible.books {
            for chapter in book.chapters {
                for verse in chapter.verses {
                    result.append(FlattenedVerse(
                        book: book.name,
                        chapter: chapter.chapter,
                        verse: verse.verse,
                        attributed: formatVerse(book: book.name, chapter: chapter.chapter, verse: verse.verse, text: verse.text)
                    ))
                }
            }
        }
        
        return result
    }
    
    static func flattenOptimizedBible(metadata: OptimizedBibleModels.BibleMetadata, chapters: [String: OptimizedBible.ChapterContent]) -> [FlattenedVerse] {
        var result: [FlattenedVerse] = []
        
        for book in metadata.books {
            for chapterNum in 1...book.chapterCount {
                if let chapter = chapters["\(book.name):\(chapterNum)"] {
                    for verse in chapter.verses {
                        result.append(FlattenedVerse(
                            book: book.name,
                            chapter: chapterNum,
                            verse: verse.verse,
                            attributed: formatVerse(book: book.name, chapter: chapterNum, verse: verse.verse, text: verse.text)
                        ))
                    }
                }
            }
        }
        
        return result
    }
    
    private static func formatVerse(book: String, chapter: Int, verse: Int, text: String) -> AttributedString {
        var attributed = AttributedString()
        
        // Only display chapter number at first verse of chapter
        if verse == 1 {
            var chapterAttr = AttributedString("\(book) \(chapter)\n")
            chapterAttr.font = .system(size: 28, weight: .bold)
            attributed.append(chapterAttr)
        }
        
        var verseAttr = AttributedString("\(verse) \(text)\n\n")
        verseAttr.font = .body
        attributed.append(verseAttr)
        
        return attributed
    }
}
