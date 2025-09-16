// filepath: BibleAppPOCV2/Utilities/TruncationDetector.swift
import SwiftUI
import UIKit

// MARK: - Truncation Detection Utility

/// Utility class for detecting text truncation in SwiftUI Text views
/// Uses NSLayoutManager to accurately measure text layout and detect where text gets cut off
class TruncationDetector {
    
    // MARK: - Truncation Detection

    /// Detect where text gets truncated in a given frame size
    ///
    /// - Parameters:
    ///   - attributedText: The text to analyze for truncation
    ///   - containerSize: The size of the container that might truncate the text
    ///   - padding: Edge insets to account for padding in the container
    /// - Returns: Tuple containing visible text and remainder text (if truncated)
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

        #if DEBUG
        print("🔍 TRUNCATION DETECTION:")
        print("   Original text length: \(nsAttributedString.length)")
        print("   Visible character range: \(characterRange)")
        print("   Container: \(availableWidth) x \(availableHeight)")
        #endif

        // Split the text at the truncation point
        if characterRange.length < nsAttributedString.length {
            // Text is truncated
            let visiblePart = nsAttributedString.attributedSubstring(from: characterRange)

            let remainderLocation = characterRange.location + characterRange.length
            let remainderLength = nsAttributedString.length - remainderLocation
            let remainderPart = remainderLength > 0 ?
                nsAttributedString.attributedSubstring(from: NSRange(location: remainderLocation, length: remainderLength)) :
                NSAttributedString()

            #if DEBUG
            print("✂️ Text truncated at character \(characterRange.length)/\(nsAttributedString.length)")
            print("   Visible: \(characterRange.length) chars")
            print("   Remainder: \(remainderLength) chars")
            #endif

            return (AttributedString(visiblePart), AttributedString(remainderPart))
        } else {
            // No truncation - all text fits
            #if DEBUG
            print("✅ All text fits, no truncation needed")
            #endif
            return (attributedText, AttributedString())
        }
    }
    
    // MARK: - Page Building with Truncation

    /// Build complete page content and detect natural truncation
    ///
    /// - Parameters:
    ///   - verses: Array of verses to include in the page
    ///   - startIndex: Index of the first verse to start from
    ///   - containerSize: Size of the page container
    ///   - bookName: Name of the book for formatting
    ///   - chapterNumber: Chapter number for formatting
    ///   - showChapterHeader: Whether to show chapter header for first verse
    ///   - showBookTitle: Whether to show book title for first verse
    ///   - carryoverText: Text from previous page that didn't fit
    /// - Returns: Tuple containing page content, remainder text, verse range, and last complete verse
    static func buildPageWithTruncation(
        verses: [DatabaseVerse],
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
            #if DEBUG
            print("📄 Starting with carryover text: \(carryover.characters.count) chars")
            #endif
        }
        
        // Add verses one by one until we find truncation
        for i in startIndex..<verses.count {
            let verse = verses[i]
            lastVerseAttempted = i
            
            let formatted = JITTextFormatter.formatVerse(
                book: bookName,
                chapter: chapterNumber,
                verse: verse.verseNumber,
                text: verse.text,
                showChapterHeader: verse.verseNumber == 1 && fullContent.characters.isEmpty && showChapterHeader,
                showBookTitle: chapterNumber == 1 && verse.verseNumber == 1 && fullContent.characters.isEmpty && showBookTitle
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
                #if DEBUG
                print("📄 Verse \(verse.verseNumber) caused truncation")
                print("📄 Last complete verse: \(lastCompleteVerse >= startIndex ? "\(verses[lastCompleteVerse].verseNumber)" : "none")")
                #endif
                return (visible, remainder, (startIndex, lastVerseAttempted), lastCompleteVerse)
            } else {
                // This verse fits completely
                fullContent = candidateContent
                lastCompleteVerse = i
                #if DEBUG
                print("📄 Verse \(verse.verseNumber) fits completely")
                #endif
            }
        }
        
        // All verses fit without truncation
        #if DEBUG
        print("📄 All verses fit, last complete: \(verses[lastCompleteVerse].verseNumber)")
        #endif
        return (fullContent, AttributedString(), (startIndex, lastVerseAttempted), lastCompleteVerse)
    }
}

