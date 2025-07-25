// filepath: BibleAppPOCV2/Services/FragmentedPageGenerator.swift
//
//  FragmentedPageGenerator.swift
//  BibleAppPOCV2
//
//  Created by refactoring from OnDemandPageGenerator.swift
//  Handles fragmented page generation with cross-page verse continuation
//

import Foundation
import SwiftUI
import CoreGraphics

/// Handles the generation of fragmented pages with cross-page verse continuation
final class FragmentedPageGenerator {
    static let shared = FragmentedPageGenerator()
    
    private init() {}
    
    /// Generate fragmented page content with cross-page verse continuation
    static func generateContent(
        startingAt key: VerseKey,
        pageSize: CGSize,
        fragmentPending: VerseFragment?,
        using loader: OptimizedBibleDataLoader = OptimizedBibleDataLoader.shared
    ) async throws -> (page: FragmentedPage, pendingFragment: VerseFragment?) {
        
        guard let chapter = await loader.loadChapterContent(book: key.book, chapter: key.chapter) else {
            throw PageGenerationError.missingChapter(key)
        }
        
        guard pageSize.width > 0 && pageSize.height > 0 else {
            throw PageGenerationError.layoutFailed(key)
        }
        
        print("📖 FRAGMENT GENERATION: Starting at \(key.description) with size \(pageSize)")
        
        // Calculate available space for fragments
        let conservativeMargin: CGFloat = 30 // Extra margin for fragment indicators
        let availableHeight = pageSize.height - (LayoutMetrics.verticalPagePadding * 2) - conservativeMargin
        let maxSize = CGSize(width: pageSize.width - (LayoutMetrics.horizontalPagePadding * 2), height: availableHeight)
        
        print("📏 FRAGMENT LAYOUT: available=\(availableHeight), maxWidth=\(maxSize.width)")
        
        var fragments: [VerseFragment] = []
        var accumulatedHeight: CGFloat = 0
        var currentVerseIndex = chapter.verses.firstIndex { $0.verse == key.verse } ?? 0
        var pendingFragmentResult: VerseFragment?
        
        // Handle pending fragment from previous page
        if let pendingFragment = fragmentPending {
            let fragmentHeight = measureFragmentHeight(pendingFragment, maxSize: maxSize)
            if accumulatedHeight + fragmentHeight <= availableHeight * 0.95 {
                fragments.append(pendingFragment)
                accumulatedHeight += fragmentHeight
                print("📏 Added pending fragment: height=\(fragmentHeight), total=\(accumulatedHeight)")
            }
        }
        
        // Process verses starting from the current position
        while currentVerseIndex < chapter.verses.count {
            let verse = chapter.verses[currentVerseIndex]
            let verseRef = VerseReference(
                unsafeBook: key.book,
                unsafeChapter: key.chapter,
                unsafeVerse: verse.verse
            )
            let domainVerse = Verse(reference: verseRef, text: verse.text)
            
            // Generate fragments for this verse
            let remainingHeight = availableHeight * 0.95 - accumulatedHeight
            let verseFragments = VerseFragmentGenerator.fragmentVerse(
                verse: domainVerse,
                availableHeight: remainingHeight,
                maxSize: maxSize
            )
            
            var addedFragments = 0
            for fragment in verseFragments {
                let fragmentHeight = measureFragmentHeight(fragment, maxSize: maxSize)
                
                if accumulatedHeight + fragmentHeight <= availableHeight * 0.95 {
                    fragments.append(fragment)
                    accumulatedHeight += fragmentHeight
                    addedFragments += 1
                    print("📏 Added fragment \(fragment.sequenceNumber + 1)/\(fragment.totalFragments): height=\(fragmentHeight), total=\(accumulatedHeight)")
                } else {
                    // This fragment doesn't fit, save it for next page
                    pendingFragmentResult = fragment
                    print("🔄 Fragment \(fragment.sequenceNumber + 1)/\(fragment.totalFragments) saved for next page")
                    break
                }
            }
            
            // If we added all fragments for this verse, move to next verse
            if addedFragments == verseFragments.count {
                currentVerseIndex += 1
            } else {
                // We have a pending fragment, stop here
                break
            }
            
            // Safety check to prevent infinite loops
            if fragments.count > 50 {
                print("⚠️ Safety break: too many fragments on one page")
                break
            }
        }
        
        // Ensure we have at least one fragment
        if fragments.isEmpty {
            print("🚨 Emergency: No fragments fit, adding first verse as single fragment")
            let verse = chapter.verses[currentVerseIndex]
            let verseRef = VerseReference(
                unsafeBook: key.book,
                unsafeChapter: key.chapter,
                unsafeVerse: verse.verse
            )
            
            let emergencyFragment = VerseFragment(
                reference: verseRef,
                textFragment: verse.text,
                isStartOfVerse: true,
                isEndOfVerse: true,
                fullVerseText: verse.text,
                sequenceNumber: 0,
                totalFragments: 1
            )
            fragments.append(emergencyFragment)
        }
        
        // Generate the combined content
        let combinedContent = VerseFragmentGenerator.combineFragments(fragments)
        
        // Create navigation title
        let startVerse = fragments.first!.reference
        let endVerse = fragments.last!.reference
        let navTitle = if startVerse.book == endVerse.book && startVerse.chapter == endVerse.chapter {
            if startVerse.verse == endVerse.verse {
                "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse)"
            } else {
                "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse)-\(endVerse.verse)"
            }
        } else if startVerse.book == endVerse.book {
            "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse) - \(endVerse.chapter):\(endVerse.verse)"
        } else {
            "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse) - \(endVerse.book) \(endVerse.chapter):\(endVerse.verse)"
        }
        
        let fragmentedPage = FragmentedPage(
            fragments: fragments,
            navTitle: navTitle,
            startVerse: startVerse,
            endVerse: endVerse,
            content: combinedContent,
            measuredHeight: accumulatedHeight,
            availableHeight: availableHeight
        )
        
        return (page: fragmentedPage, pendingFragment: pendingFragmentResult)
    }
    
    /// Measure the height of a fragment for layout calculations
    private static func measureFragmentHeight(_ fragment: VerseFragment, maxSize: CGSize) -> CGFloat {
        let formatted = JITTextFormatter.formatVerse(
            book: fragment.reference.book,
            chapter: fragment.reference.chapter,
            verse: fragment.reference.verse,
            text: fragment.displayText
        )
        
        return JITTextFormatter.measureText(formatted, maxSize: maxSize).height
    }
}
