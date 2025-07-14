//
//  PageContentGenerator.swift
//  BibleAppPOCV2
//
//  Created by refactoring from OnDemandPageGenerator.swift
//  Handles page content generation and formatting logic
//

import Foundation
import SwiftUI
import CoreGraphics

/// Handles the generation of page content from Bible data
final class PageContentGenerator {
    static let shared = PageContentGenerator()
    
    private init() {}
    
    /// Generate page content starting from a specific verse
    static func generate(
        from key: VerseKey,
        pageSize: CGSize,
        tail: AttributedString? = nil,
        using loader: OptimizedBibleDataLoader = OptimizedBibleDataLoader.shared
    ) async -> Result<(page: GeneratedPage, remainder: (key: VerseKey, text: AttributedString)?), PageGenerationError> {
        
        guard let chapter = await loader.loadChapterContent(book: key.book, chapter: key.chapter) else {
            return .failure(.missingChapter(key))
        }
        
        guard pageSize.width > 0 && pageSize.height > 0 else {
            return .failure(.layoutFailed(key))
        }
        
        print("📖 DYNAMIC HEIGHT: Starting page at \(key.description) with size \(pageSize)")
        
        let startVerseIndex = chapter.verses.firstIndex { $0.verse == key.verse } ?? 0
        
        // PRECISION-FIRST PAGINATION: Use exact SwiftUI Text rendering measurements
        // WHY: Eliminates the overflow feedback loop and ensures headers show exactly visible verses
        
        // Calculate available height with extra conservative margin to prevent any overflow
        let conservativeMargin: CGFloat = 20 // Extra safety margin for SwiftUI rendering variations
        let availableHeight = pageSize.height - (LayoutMetrics.verticalPagePadding * 2) - conservativeMargin
        let maxSize = CGSize(width: pageSize.width - (LayoutMetrics.horizontalPagePadding * 2), height: availableHeight)
        
        print("📏 PRECISE LAYOUT: available=\(availableHeight), maxWidth=\(maxSize.width)")
        
        var segments: [PageSegment] = []
        var accumulatedHeight: CGFloat = 0
        var lastCompleteVerseIndex = startVerseIndex - 1
        
        // Add carryover segment if there was one
        if let carryover = tail, !carryover.characters.isEmpty {
            let carryoverHeight = JITTextFormatter.measureText(carryover, maxSize: maxSize).height
            // Extra conservative check - use 95% of available height to be safe
            if accumulatedHeight + carryoverHeight <= availableHeight * 0.95 {
                segments.append(PageSegment(attributed: carryover, verseKey: key, isSplit: true))
                accumulatedHeight += carryoverHeight
                print("📏 Added carryover: height=\(carryoverHeight), total=\(accumulatedHeight)")
            } else {
                print("🚫 Carryover too tall, skipping: \(carryoverHeight) > \(availableHeight * 0.95)")
            }
        }
        
        // Accumulate verses with CONSERVATIVE height checking to prevent any overflow
        for i in startVerseIndex..<chapter.verses.count {
            let verse = chapter.verses[i]
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse)
            
            let formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verse,
                text: verse.text,
                showChapterHeader: verse.verse == 1 && segments.isEmpty,
                showBookTitle: key.chapter == 1 && verse.verse == 1 && segments.isEmpty
            )
            
            // Measure this verse's actual height
            let verseHeight = JITTextFormatter.measureText(formatted, maxSize: maxSize).height
            
            // CONSERVATIVE CHECK: Use 95% of available height to prevent any overflow
            let heightLimit = availableHeight * 0.95
            if accumulatedHeight + verseHeight <= heightLimit {
                segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
                accumulatedHeight += verseHeight
                lastCompleteVerseIndex = i
                print("📏 Added verse \(verse.verse): height=\(verseHeight), total=\(accumulatedHeight)/\(heightLimit)")
            } else {
                print("🛑 CONSERVATIVE STOP: Verse \(verse.verse) would exceed 95% limit")
                print("    Height needed: \(verseHeight), Available: \(heightLimit - accumulatedHeight)")
                break
            }
        }
        
        // Emergency fallback - ensure we have at least one verse
        if segments.isEmpty {
            let verse = chapter.verses[startVerseIndex]
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse)
            
            let formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verse,
                text: verse.text,
                showChapterHeader: verse.verse == 1,
                showBookTitle: key.chapter == 1 && verse.verse == 1
            )
            
            segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
            lastCompleteVerseIndex = startVerseIndex
            print("🚨 Emergency fallback: added verse \(verse.verse) (page must have at least one verse)")
        }
        
        // Handle remainder - continue from the next verse that didn't fit
        let remainder: (key: VerseKey, text: AttributedString)? = {
            let nextVerseIndex = lastCompleteVerseIndex + 1
            if nextVerseIndex < chapter.verses.count {
                let nextVerse = chapter.verses[nextVerseIndex]
                return (key: VerseKey(book: key.book, chapter: key.chapter, verse: nextVerse.verse), text: AttributedString())
            } else {
                return nil // No more verses in this chapter
            }
        }()
        
        let startVerse = chapter.verses[startVerseIndex]
        let endVerse = chapter.verses[lastCompleteVerseIndex]
        
        let page = GeneratedPage(
            segments: segments,
            startKey: VerseKey(book: key.book, chapter: key.chapter, verse: startVerse.verse),
            navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false)
        )
        
        print("📄 PRECISION RESULT: verses \(startVerse.verse)-\(endVerse.verse) (\(segments.count) verses)")
        print("📄 Conservative height used: \(accumulatedHeight) of \(availableHeight * 0.95) limit")
        print("📄 Actual available space: \(availableHeight) (with \(conservativeMargin)pt safety margin)")
        print("📄 Has remainder: \(remainder != nil)")
        
        return .success((page: page, remainder: remainder))
    }
}
