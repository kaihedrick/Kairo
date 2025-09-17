// filepath: BibleAppPOCV2/Services/PageContentGenerator.swift
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
@MainActor
final class PageContentGenerator {
    static let shared = PageContentGenerator()
    
    private init() {}
    
    /// Generate page content starting from a specific verse
    static func generate(
        from key: VerseKey,
        pageSize: CGSize,
        tail: AttributedString? = nil,
        using loader: DatabaseBibleDataLoader
    ) async -> Result<(page: GeneratedPage, remainder: (key: VerseKey, text: AttributedString)?), PageGenerationError> {
        
        let result = await loader.loadChapter(book: key.book, chapter: key.chapter)
        guard case .success(let chapter) = result else {
            return .failure(.missingChapter(key))
        }
        
        guard pageSize.width > 0 && pageSize.height > 0 else {
            return .failure(.layoutFailed(key))
        }
        
        print("📖 DYNAMIC HEIGHT: Starting page at \(key.description) with size \(pageSize)")
        
        let startVerseIndex = chapter.verses.firstIndex { $0.verseNumber == key.verse } ?? 0

        #if DEBUG
        print("🎯 PAGE GENERATION: Starting at verse \(key.verse), found index \(startVerseIndex)")
        print("📚 CHAPTER INFO: \(chapter.verses.count) total verses, starting from index \(startVerseIndex)")
        if startVerseIndex < chapter.verses.count {
            let startVerse = chapter.verses[startVerseIndex]
            print("🎯 START VERSE: \(startVerse.verseNumber) - '\(startVerse.text.prefix(50))...'")
        }
        #endif

        // PRECISION-FIRST PAGINATION: Use exact SwiftUI Text rendering measurements
        // WHY: Eliminates the overflow feedback loop and ensures headers show exactly visible verses

        // Calculate available height with MORE GENEROUS margin to allow multiple verses per page
        let conservativeMargin: CGFloat = 20 // Extra safety margin for SwiftUI rendering variations
        let availableHeight = pageSize.height - (LayoutMetrics.verticalPagePadding * 2) - conservativeMargin
        let maxSize = CGSize(width: pageSize.width - (LayoutMetrics.horizontalPagePadding * 2), height: availableHeight)

        print("📏 PRECISE LAYOUT: available=\(availableHeight), maxWidth=\(maxSize.width)")
        print("📏 Page size: \(pageSize.width) x \(pageSize.height), margins: \(LayoutMetrics.horizontalPagePadding)h + \(LayoutMetrics.verticalPagePadding)v")
        
        var segments: [PageSegment] = []
        var accumulatedHeight: CGFloat = 0  // ✅ Reset per page
        var lastCompleteVerseIndex = startVerseIndex - 1

        #if DEBUG
        print("🔄 PAGE ACCUMULATORS RESET:")
        print("   accumulatedHeight: \(accumulatedHeight)")
        print("   maxAllowed: \(availableHeight * 0.90)")
        print("   heightLimit: \(availableHeight * 0.90)")
        #endif
        
        // Add carryover segment if there was one
        if let carryover = tail, !carryover.characters.isEmpty {
            let carryoverHeight = JITTextFormatter.measureText(carryover, maxSize: maxSize).height
            // Use same 90% limit for consistency
            if accumulatedHeight + carryoverHeight <= availableHeight * 0.90 {
                segments.append(PageSegment(attributed: carryover, verseKey: key, isSplit: true))
                accumulatedHeight += carryoverHeight
                print("📏 Added carryover: height=\(carryoverHeight), total=\(accumulatedHeight)")
            } else {
                print("🚫 Carryover too tall, skipping: \(carryoverHeight) > \(availableHeight * 0.90)")
            }
        }
        
        // Accumulate verses with CONSERVATIVE height checking to prevent any overflow
        #if DEBUG
        print("🔄 STARTING VERSE ACCUMULATION: from verse \(chapter.verses[startVerseIndex].verseNumber) (\(chapter.verses.count - startVerseIndex) verses available)")
        #endif

        for i in startVerseIndex..<chapter.verses.count {
            let verse = chapter.verses[i]
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verseNumber)

            #if DEBUG
            print("🔍 PROCESSING VERSE \(verse.verseNumber): '\(verse.text.prefix(30))...'")
            #endif

            let formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verseNumber,
                text: verse.text,
                showChapterHeader: verse.verseNumber == 1 && segments.isEmpty,
                showBookTitle: key.chapter == 1 && verse.verseNumber == 1 && segments.isEmpty
            )

            // Measure this verse's actual height
            let verseHeight = JITTextFormatter.measureText(formatted, maxSize: maxSize).height

            // LESS CONSERVATIVE CHECK: Use 90% of available height to allow more verses per page
            let heightLimit = availableHeight * 0.90
            if accumulatedHeight + verseHeight <= heightLimit {
                segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
                accumulatedHeight += verseHeight
                lastCompleteVerseIndex = i
                print("📏 Added verse \(verse.verseNumber): height=\(String(format: "%.1f", verseHeight)), total=\(String(format: "%.1f", accumulatedHeight))/\(String(format: "%.1f", heightLimit)) (90% limit)")
            } else {
                print("🛑 PAGINATION STOP: Verse \(verse.verseNumber) would exceed 90% limit (\(String(format: "%.1f", verseHeight)) needed, \(String(format: "%.1f", heightLimit - accumulatedHeight)) available)")
                break
            }
        }

        #if DEBUG
        print("📊 PAGE ACCUMULATION COMPLETE: \(segments.count) verses, height \(String(format: "%.1f", accumulatedHeight))")
        let verseNumbers = segments.map { $0.verseKey.verse }
        print("📋 VERSE NUMBERS: \(verseNumbers)")
        #endif
        
        // Emergency fallback - ensure we have at least one verse
        if segments.isEmpty {
            let verse = chapter.verses[startVerseIndex]
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verseNumber)
            
            let formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verseNumber,
                text: verse.text,
                showChapterHeader: verse.verseNumber == 1,
                showBookTitle: key.chapter == 1 && verse.verseNumber == 1
            )
            
            segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
            lastCompleteVerseIndex = startVerseIndex
            print("🚨 Emergency fallback: added verse \(verse.verseNumber) (page must have at least one verse)")
        }
        
        // Handle remainder - continue from the next verse that didn't fit
        let remainder: (key: VerseKey, text: AttributedString)? = {
            let nextVerseIndex = lastCompleteVerseIndex + 1
            if nextVerseIndex < chapter.verses.count {
                let nextVerse = chapter.verses[nextVerseIndex]
                return (key: VerseKey(book: key.book, chapter: key.chapter, verse: nextVerse.verseNumber), text: AttributedString())
            } else {
                return nil // No more verses in this chapter
            }
        }()
        
        let startVerse = chapter.verses[startVerseIndex]
        let endVerse = chapter.verses[lastCompleteVerseIndex]
        
        let page = GeneratedPage(
            segments: segments,
            startKey: VerseKey(book: key.book, chapter: key.chapter, verse: startVerse.verseNumber),
            navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false)
        )
        
        print("📄 PRECISION RESULT: verses \(startVerse.verseNumber)-\(endVerse.verseNumber) (\(segments.count) verses)")
        print("📄 Height used: \(String(format: "%.1f", accumulatedHeight)) of \(String(format: "%.1f", availableHeight * 0.90)) limit (90%)")
        print("📄 Actual available space: \(String(format: "%.1f", availableHeight)) (with \(conservativeMargin)pt safety margin)")
        print("📄 Has remainder: \(remainder != nil)")
        if let remainder = remainder {
            print("📄 Next page starts at: \(remainder.key.description)")
        }
        
        return .success((page: page, remainder: remainder))
    }
}
