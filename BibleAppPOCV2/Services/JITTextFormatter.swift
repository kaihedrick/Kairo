// JITTextFormatter.swift
// Utility for building and measuring AttributedStrings representing verses.

import Foundation
import SwiftUI

/// Formats verses for on-demand pagination and caches measurements.
class JITTextFormatter {
    private static let measurementCache = LRUCache<String, CGSize>(capacity: 100)

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
            bookAttr.font = .system(size: 32, weight: .bold)
            bookAttr.foregroundColor = .primary
            attributed.append(bookAttr)
        }

        if showChapterHeader {
            var chapterAttr = AttributedString("\(chapter) ")
            chapterAttr.font = .system(size: 28, weight: .bold)
            chapterAttr.foregroundColor = .primary
            attributed.append(chapterAttr)
        }

        var verseNumberAttr = AttributedString("\(verse) ")
        verseNumberAttr.font = .system(size: 12, weight: .semibold)
        verseNumberAttr.foregroundColor = .secondary

        var verseTextAttr = AttributedString("\(text) ")
        verseTextAttr.font = .body
        verseTextAttr.foregroundColor = .primary

        attributed.append(verseNumberAttr)
        attributed.append(verseTextAttr)

        return attributed
    }

    /// Measure the rendered size of an attributed string.
    static func measureText(_ text: AttributedString, maxSize: CGSize) -> CGSize {
        if text.characters.isEmpty { return .zero }
        let cacheKey = "\(text.characters.count):\(maxSize.width):\(maxSize.height)"
        if let cached = measurementCache.get(cacheKey) { return cached }

        let nsAttr = NSAttributedString(text)
        let drawingOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let drawingRect = nsAttr.boundingRect(
            with: CGSize(width: maxSize.width, height: .greatestFiniteMagnitude),
            options: drawingOptions,
            context: nil
        )

        let size = CGSize(width: ceil(drawingRect.width), height: ceil(drawingRect.height))
        measurementCache.set(cacheKey, size)
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
