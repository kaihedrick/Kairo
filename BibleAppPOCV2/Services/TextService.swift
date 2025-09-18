// filepath: BibleAppPOCV2/Services/TextService.swift
// TextService.swift
// Text formatting service for consistent verse styling

import SwiftUI
import Foundation

/// Text formatting service for consistent verse styling
struct TextService {
    func formatVerse(_ verse: DatabaseVerse, showChapterHeader: Bool, showBookTitle: Bool) -> AttributedString {
        var out = AttributedString("")
        
        // Verse number styling (small caps / semibold / baseline shift if desired)
        var num = AttributedString("\(verse.verseNumber) ")
        num.font = Typography.verseNumber
        num.foregroundColor = .secondary
        
        // Body
        var body = AttributedString(verse.text)
        body.font = Typography.body
        
        out += num
        out += body
        
        // Add trailing space to preserve paragraph flow between verses
        var spacer = AttributedString(" ")
        spacer.font = Typography.body
        out += spacer
        
        return out
    }
    
    func measureText(_ text: AttributedString, containerSize: CGSize) -> CGSize { 
        .zero 
    }
    
    func formatVerseRange(_ verses: [DatabaseVerse]) -> AttributedString { 
        AttributedString("") 
    }
}
