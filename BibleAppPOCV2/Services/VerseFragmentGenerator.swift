//
//  VerseFragmentGenerator.swift
//  BibleAppPOCV2
//
//  Created by Fragment System on 7/12/25.
//  Intelligent verse splitting for cross-page continuation
//

import Foundation
import SwiftUI

/// Generates verse fragments for optimal page layout
public class VerseFragmentGenerator {
    
    /// Sentence delimiters for natural breaking points
    private static let sentenceDelimiters: Set<Character> = [
        ".", "!", "?", ":", ";", 
        ".", "!", "?", "：", "；", // Unicode variants
        "…", "‼", "⁇", "⁈", "⁉"  // Extended punctuation
    ]
    
    /// Natural break points (prefer these over arbitrary word breaks)
    private static let naturalBreakPoints: Set<String> = [
        " and ", " but ", " for ", " yet ", " so ", " or ", " nor ",
        " because ", " therefore ", " however ", " moreover ", " furthermore ",
        " thus ", " hence ", " consequently ", " meanwhile ", " nevertheless ",
        " behold ", " lo ", " verily ", " truly ", " indeed ", " surely "
    ]
    
    /// Minimum fragment length to avoid tiny fragments
    private static let minimumFragmentLength: Int = 20
    
    /// Maximum fragment length before forced break
    private static let maximumFragmentLength: Int = 500
    
    /// Split a verse into fragments based on available space
    /// - Parameters:
    ///   - verse: The verse to fragment
    ///   - availableHeight: Height available for content
    ///   - maxSize: Maximum size for text measurement
    /// - Returns: Array of fragments that fit within height constraints
    public static func fragmentVerse(
        verse: Verse,
        availableHeight: CGFloat,
        maxSize: CGSize
    ) -> [VerseFragment] {
        let fullText = verse.text
        
        // If the entire verse fits, return it as a single fragment
        let fullAttributedText = JITTextFormatter.formatVerse(
            book: verse.reference.book,
            chapter: verse.reference.chapter,
            verse: verse.reference.verse,
            text: fullText
        )
        
        let fullHeight = JITTextFormatter.measureText(fullAttributedText, maxSize: maxSize).height
        
        if fullHeight <= availableHeight {
            return [VerseFragment(
                reference: verse.reference,
                textFragment: fullText,
                isStartOfVerse: true,
                isEndOfVerse: true,
                fullVerseText: fullText,
                sequenceNumber: 0,
                totalFragments: 1
            )]
        }
        
        // Verse needs to be split - find optimal break points
        let fragments = splitVerseIntoFragments(
            verse: verse,
            availableHeight: availableHeight,
            maxSize: maxSize
        )
        
        return fragments
    }
    
    /// Split a verse into multiple fragments using intelligent break points
    private static func splitVerseIntoFragments(
        verse: Verse,
        availableHeight: CGFloat,
        maxSize: CGSize
    ) -> [VerseFragment] {
        let fullText = verse.text
        var fragments: [VerseFragment] = []
        var remainingText = fullText
        var sequenceNumber = 0
        
        // Reserve some height for continuation indicators
        let fragmentHeight = availableHeight * 0.95
        
        while !remainingText.isEmpty {
            let (fragmentText, isComplete) = findOptimalFragment(
                text: remainingText,
                availableHeight: fragmentHeight,
                maxSize: maxSize,
                verse: verse
            )
            
            if fragmentText.isEmpty {
                // Emergency fallback - take at least one word
                let words = remainingText.components(separatedBy: .whitespaces)
                let emergencyText = words.first ?? remainingText
                
                fragments.append(VerseFragment(
                    reference: verse.reference,
                    textFragment: emergencyText,
                    isStartOfVerse: sequenceNumber == 0,
                    isEndOfVerse: emergencyText == remainingText,
                    fullVerseText: fullText,
                    sequenceNumber: sequenceNumber,
                    totalFragments: 1 // Will be updated later
                ))
                
                remainingText = String(remainingText.dropFirst(emergencyText.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            
            fragments.append(VerseFragment(
                reference: verse.reference,
                textFragment: fragmentText,
                isStartOfVerse: sequenceNumber == 0,
                isEndOfVerse: isComplete,
                fullVerseText: fullText,
                sequenceNumber: sequenceNumber,
                totalFragments: 1 // Will be updated later
            ))
            
            if isComplete {
                break
            }
            
            remainingText = String(remainingText.dropFirst(fragmentText.count)).trimmingCharacters(in: .whitespaces)
            sequenceNumber += 1
        }
        
        // Update total fragments count
        let totalFragments = fragments.count
        return fragments.map { fragment in
            VerseFragment(
                reference: fragment.reference,
                textFragment: fragment.textFragment,
                isStartOfVerse: fragment.isStartOfVerse,
                isEndOfVerse: fragment.isEndOfVerse,
                fullVerseText: fragment.fullVerseText,
                sequenceNumber: fragment.sequenceNumber,
                totalFragments: totalFragments
            )
        }
    }
    
    /// Find the optimal fragment that fits within available height
    private static func findOptimalFragment(
        text: String,
        availableHeight: CGFloat,
        maxSize: CGSize,
        verse: Verse
    ) -> (fragment: String, isComplete: Bool) {
        
        // Try sentence-based splits first
        if let sentenceFragment = findSentenceFragment(
            text: text,
            availableHeight: availableHeight,
            maxSize: maxSize,
            verse: verse
        ) {
            return sentenceFragment
        }
        
        // Try natural break points
        if let naturalFragment = findNaturalBreakFragment(
            text: text,
            availableHeight: availableHeight,
            maxSize: maxSize,
            verse: verse
        ) {
            return naturalFragment
        }
        
        // Fall back to word-based splits
        return findWordFragment(
            text: text,
            availableHeight: availableHeight,
            maxSize: maxSize,
            verse: verse
        )
    }
    
    /// Find fragment at sentence boundaries
    private static func findSentenceFragment(
        text: String,
        availableHeight: CGFloat,
        maxSize: CGSize,
        verse: Verse
    ) -> (fragment: String, isComplete: Bool)? {
        
        var bestFragment = ""
        var bestLength = 0
        
        for (index, character) in text.enumerated() {
            if sentenceDelimiters.contains(character) {
                let candidate = String(text.prefix(index + 1))
                
                // Skip if too short
                if candidate.count < minimumFragmentLength {
                    continue
                }
                
                let attributed = JITTextFormatter.formatVerse(
                    book: verse.reference.book,
                    chapter: verse.reference.chapter,
                    verse: verse.reference.verse,
                    text: candidate
                )
                
                let height = JITTextFormatter.measureText(attributed, maxSize: maxSize).height
                
                if height <= availableHeight {
                    bestFragment = candidate
                    bestLength = candidate.count
                } else {
                    break
                }
            }
        }
        
        if !bestFragment.isEmpty {
            let isComplete = bestLength >= text.count
            return (bestFragment, isComplete)
        }
        
        return nil
    }
    
    /// Find fragment at natural break points
    private static func findNaturalBreakFragment(
        text: String,
        availableHeight: CGFloat,
        maxSize: CGSize,
        verse: Verse
    ) -> (fragment: String, isComplete: Bool)? {
        
        var bestFragment = ""
        var bestLength = 0
        
        for breakPoint in naturalBreakPoints {
            if let range = text.range(of: breakPoint) {
                let candidate = String(text[..<range.upperBound])
                
                if candidate.count < minimumFragmentLength {
                    continue
                }
                
                let attributed = JITTextFormatter.formatVerse(
                    book: verse.reference.book,
                    chapter: verse.reference.chapter,
                    verse: verse.reference.verse,
                    text: candidate
                )
                
                let height = JITTextFormatter.measureText(attributed, maxSize: maxSize).height
                
                if height <= availableHeight && candidate.count > bestLength {
                    bestFragment = candidate
                    bestLength = candidate.count
                }
            }
        }
        
        if !bestFragment.isEmpty {
            let isComplete = bestLength >= text.count
            return (bestFragment, isComplete)
        }
        
        return nil
    }
    
    /// Find fragment at word boundaries (fallback)
    private static func findWordFragment(
        text: String,
        availableHeight: CGFloat,
        maxSize: CGSize,
        verse: Verse
    ) -> (fragment: String, isComplete: Bool) {
        
        let words = text.components(separatedBy: .whitespaces)
        var currentFragment = ""
        var wordCount = 0
        
        for word in words {
            let candidate = currentFragment.isEmpty ? word : currentFragment + " " + word
            
            let attributed = JITTextFormatter.formatVerse(
                book: verse.reference.book,
                chapter: verse.reference.chapter,
                verse: verse.reference.verse,
                text: candidate
            )
            
            let height = JITTextFormatter.measureText(attributed, maxSize: maxSize).height
            
            if height <= availableHeight {
                currentFragment = candidate
                wordCount += 1
            } else {
                break
            }
        }
        
        // If we couldn't fit any words, take the first word anyway
        if currentFragment.isEmpty && !words.isEmpty {
            currentFragment = words[0]
            wordCount = 1
        }
        
        let isComplete = wordCount >= words.count
        return (currentFragment, isComplete)
    }
    
    /// Combine multiple fragments into a single attributed string for rendering
    public static func combineFragments(
        _ fragments: [VerseFragment]
    ) -> AttributedString {
        var combined = AttributedString()
        
        for (index, fragment) in fragments.enumerated() {
            let formatted = JITTextFormatter.formatVerse(
                book: fragment.reference.book,
                chapter: fragment.reference.chapter,
                verse: fragment.reference.verse,
                text: fragment.displayText
            )
            
            if index > 0 {
                combined += AttributedString("\n")
            }
            
            combined += formatted
        }
        
        return combined
    }
}
