import SwiftUI
import UIKit

class TruncationDetector {
    
    /// Detect where text gets truncated in a given frame size
    static func findTruncationPoint(
        attributedText: AttributedString,
        containerSize: CGSize,
        padding: EdgeInsets
    ) -> (visibleText: AttributedString, remainderText: AttributedString) {
        
        if attributedText.characters.isEmpty {
            return (AttributedString(), AttributedString())
        }
        
        let availableWidth = containerSize.width - padding.leading - padding.trailing
        let availableHeight = containerSize.height - padding.top - padding.bottom
        
        let nsAttributedString = NSMutableAttributedString(attributedText)
        
        // Create text container with exact same constraints as SwiftUI Text view
        let textContainer = NSTextContainer(size: CGSize(width: availableWidth, height: availableHeight))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0  // No artificial line limit
        textContainer.lineBreakMode = .byWordWrapping
        
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage(attributedString: nsAttributedString)
        
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        
        // Force layout calculation
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        print("🔍 TRUNCATION DETECTION:")
        print("   Original text length: \(nsAttributedString.length)")
        print("   Visible character range: \(characterRange)")
        print("   Container: \(availableWidth) x \(availableHeight)")
        
        // Split the text at the truncation point
        if characterRange.length < nsAttributedString.length {
            // Text is truncated
            let visiblePart = nsAttributedString.attributedSubstring(from: characterRange)
            
            let remainderLocation = characterRange.location + characterRange.length
            let remainderLength = nsAttributedString.length - remainderLocation
            let remainderPart = remainderLength > 0 ? 
                nsAttributedString.attributedSubstring(from: NSRange(location: remainderLocation, length: remainderLength)) :
                NSAttributedString()
            
            print("✂️ Text truncated at character \(characterRange.length)/\(nsAttributedString.length)")
            print("   Visible: \(characterRange.length) chars")
            print("   Remainder: \(remainderLength) chars")
            
            return (AttributedString(visiblePart), AttributedString(remainderPart))
        } else {
            // No truncation - all text fits
            print("✅ All text fits, no truncation needed")
            return (attributedText, AttributedString())
        }
    }
    
    /// Build complete page content and detect natural truncation
    static func buildPageWithTruncation(
        verses: [OptimizedBible.Verse],
        startingAt startIndex: Int,
        containerSize: CGSize,
        bookName: String,
        chapterNumber: Int,
        showChapterHeader: Bool = false,
        showBookTitle: Bool = false,
        carryoverText: AttributedString? = nil
    ) -> (pageContent: AttributedString, remainderText: AttributedString, verseRange: (start: Int, end: Int), lastCompleteVerse: Int) {
        
        var fullContent = AttributedString()
        var lastVerseAttempted = startIndex
        var lastCompleteVerse = startIndex - 1  // Start before the first verse
        
        // Add carryover text from previous page if any
        if let carryover = carryoverText, !carryover.characters.isEmpty {
            fullContent = carryover
            print("📄 Starting with carryover text: \(carryover.characters.count) chars")
        }
        
        // Add verses one by one until we find truncation
        for i in startIndex..<verses.count {
            let verse = verses[i]
            lastVerseAttempted = i
            
            let formatted = JITTextFormatter.formatVerse(
                book: bookName,
                chapter: chapterNumber,
                verse: verse.verse,
                text: verse.text,
                showChapterHeader: verse.verse == 1 && fullContent.characters.isEmpty && showChapterHeader,
                showBookTitle: chapterNumber == 1 && verse.verse == 1 && fullContent.characters.isEmpty && showBookTitle
            )
            
            let candidateContent = fullContent + formatted
            
            // Test for truncation
            let padding = EdgeInsets(
                top: LayoutMetrics.verticalPagePadding,
                leading: LayoutMetrics.horizontalPagePadding,
                bottom: LayoutMetrics.verticalPagePadding,
                trailing: LayoutMetrics.horizontalPagePadding
            )
            
            let (visible, remainder) = findTruncationPoint(
                attributedText: candidateContent,
                containerSize: containerSize,
                padding: padding
            )
            
            if !remainder.characters.isEmpty {
                // This verse caused truncation
                print("📄 Verse \(verse.verse) caused truncation")
                print("📄 Last complete verse: \(lastCompleteVerse >= startIndex ? "\(verses[lastCompleteVerse].verse)" : "none")")
                return (visible, remainder, (startIndex, lastVerseAttempted), lastCompleteVerse)
            } else {
                // This verse fits completely
                fullContent = candidateContent
                lastCompleteVerse = i
                print("📄 Verse \(verse.verse) fits completely")
            }
        }
        
        // All verses fit without truncation
        print("📄 All verses fit, last complete: \(verses[lastCompleteVerse].verse)")
        return (fullContent, AttributedString(), (startIndex, lastVerseAttempted), lastCompleteVerse)
    }
}

