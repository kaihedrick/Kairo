// filepath: BibleAppPOCV2/Services/JITTextFormatter.swift
// JITTextFormatter.swift
// Utility for building and measuring AttributedStrings representing verses.

import Foundation
import SwiftUI
import UIKit
import CoreText

/// Formats verses for on-demand pagination and caches measurements.
class JITTextFormatter {
    private static let measurementCache = LRUCache<String, CGSize>(capacity: 100)
    
    // Debug flag to disable all caching for accurate measurements
    private static let disableCaching = true

    /// Format a single verse into an attributed string with optional headers.
    static func formatVerse(
        book: String,
        chapter: Int,
        verse: Int,
        text: String,
        showChapterHeader: Bool = false,
        showBookTitle: Bool = false
    ) -> AttributedString {
        var attributed = AttributedString()

        if showBookTitle {
            var bookAttr = AttributedString("\(book)\n\n")
            bookAttr.font = Typography.bookTitle
            bookAttr.foregroundColor = .primary
            attributed.append(bookAttr)
        }

        if showChapterHeader {
            var chapterAttr = AttributedString("\(chapter) ")
            chapterAttr.font = Typography.chapter
            chapterAttr.foregroundColor = .primary
            attributed.append(chapterAttr)
        }

        var verseNumberAttr = AttributedString("\(verse) ")
        verseNumberAttr.font = Typography.verseNumber
        verseNumberAttr.foregroundColor = .secondary

        // Create verse text with line spacing using NSAttributedString first, then convert
        let style = NSMutableParagraphStyle()
        style.lineSpacing = Typography.lineSpacing
        
        let nsAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .paragraphStyle: style,
            .foregroundColor: UIColor.label
        ]
        
        let nsVerseText = NSAttributedString(string: "\(text) ", attributes: nsAttributes)
        let verseTextAttr = AttributedString(nsVerseText)

        attributed.append(verseNumberAttr)
        attributed.append(verseTextAttr)

        return attributed
    }

    /// Measure the rendered size of an attributed string.
    static func measureText(_ text: AttributedString, maxSize: CGSize) -> CGSize {
        if text.characters.isEmpty { return .zero }
        
        // Force fresh measurement if caching is disabled
        if disableCaching {
            return performFreshMeasurement(text, maxSize: maxSize)
        }
        
        // Create a proper cache key using content and size
        let contentStr = String(text.characters)
        let contentHash = contentStr.hash
        let cacheKey = "\(contentHash):\(maxSize.width):\(maxSize.height)"
        if let cached = measurementCache.get(cacheKey) { 
            print("📋 Using cached measurement for \(text.characters.prefix(20))...")
            return cached 
        }
        
        let size = performFreshMeasurement(text, maxSize: maxSize)
        measurementCache.set(cacheKey, size)
        return size
    }
    
    /// Perform actual measurement without caching
    private static func performFreshMeasurement(_ text: AttributedString, maxSize: CGSize) -> CGSize {
        // Only log for very short text or every 10th measurement
        if text.characters.count < 50 || Int.random(in: 1...10) == 1 {
            print("🔍 FRESH measurement for text: \(text.characters.prefix(50))... maxSize: \(maxSize)")
        }
        
        // Convert to NSAttributedString for measurement
        let nsAttr = NSAttributedString(text)
        
        // Use CTFramesetter for accurate measurement, then add conservative padding
        let framesetter = CTFramesetterCreateWithAttributedString(nsAttr)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: nsAttr.length),
            nil, // no additional attributes
            CGSize(width: maxSize.width, height: .greatestFiniteMagnitude),
            nil  // don't need the range that fits
        )
        
        // Add conservative padding to account for SwiftUI Text rendering variations
        let conservativePadding: CGFloat = 4.0
        let size = CGSize(
            width: ceil(suggestedSize.width) + conservativePadding, 
            height: ceil(suggestedSize.height) + conservativePadding
        )
        if text.characters.count < 50 || Int.random(in: 1...10) == 1 {
            print("🔍 FRESH result: \(size)")
        }
        return size
    }

    /// Convenience wrapper for plain strings.
    static func measureText(_ text: String, maxSize: CGSize) -> CGSize {
        measureText(AttributedString(text), maxSize: maxSize)
    }

    /// Clear cached measurement results.
    static func clearCache() {
        measurementCache.clear()
    }
    
    /// Measure text as it would actually render in a Text view with padding
    static func measureActualRender(_ text: AttributedString, containerSize: CGSize, padding: EdgeInsets) -> CGSize {
        if text.characters.isEmpty { return .zero }
        
        // Account for padding in available space
        let availableWidth = max(containerSize.width - padding.leading - padding.trailing, 0)
        let nsAttr = NSAttributedString(text)
        
        // Use CTFramesetter for measurement that matches SwiftUI Text rendering
        let framesetter = CTFramesetterCreateWithAttributedString(nsAttr)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: nsAttr.length),
            nil,
            CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            nil
        )
        
        // Add padding back to get total size
        let totalWidth = ceil(suggestedSize.width) + padding.leading + padding.trailing
        let totalHeight = ceil(suggestedSize.height) + padding.top + padding.bottom
        
        return CGSize(width: totalWidth, height: totalHeight)
    }
    
    /// Debug method to compare our measurement with SwiftUI's actual rendering
    static func debugMeasurement(_ text: AttributedString, containerSize: CGSize, padding: EdgeInsets) -> (predicted: CGSize, shouldBeAccurate: Bool) {
        let predicted = measureActualRender(text, containerSize: containerSize, padding: padding)
        
        // Additional validation: check if our measurement logic is reasonable
        let contentHeight = predicted.height - padding.top - padding.bottom
        let containerHeight = containerSize.height
        
        let isReasonable = contentHeight > 0 && contentHeight <= containerHeight + 50 // 50pt tolerance
        
        print("🔬 MEASUREMENT DEBUG:")
        print("   Container: \(containerSize)")
        print("   Padding: top=\(padding.top), bottom=\(padding.bottom)")
        print("   Predicted total: \(predicted)")
        print("   Content height: \(contentHeight)")
        print("   Reasonable: \(isReasonable)")
        
        return (predicted, isReasonable)
    }

    /// Split an attributed string into the portion that fits within the given size
    /// and the remaining text.
    static func split(
        attributed: AttributedString,
        maxSize: CGSize
    ) -> (fitting: AttributedString, remainder: AttributedString) {
        if attributed.characters.isEmpty { return (.init(), .init()) }

        let nsAttr = NSMutableAttributedString(attributed)
        let storage = NSTextStorage(attributedString: nsAttr)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: maxSize)
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        // Force layout calculation
        layout.glyphRange(for: container)
        let glyphRange = layout.glyphRange(forBoundingRect: CGRect(origin: .zero, size: maxSize), in: container)
        let charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let fitting = nsAttr.attributedSubstring(from: charRange)

        let remainderLocation = charRange.location + charRange.length
        let remainderLength = nsAttr.length - remainderLocation
        let remainder: NSAttributedString
        if remainderLength > 0 {
            remainder = nsAttr.attributedSubstring(from: NSRange(location: remainderLocation, length: remainderLength))
        } else {
            remainder = NSAttributedString()
        }

        return (AttributedString(fitting), AttributedString(remainder))
    }
}
