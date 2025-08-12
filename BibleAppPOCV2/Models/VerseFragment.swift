// filepath: BibleAppPOCV2/Models/VerseFragment.swift
//
//  VerseFragment.swift
//  BibleAppPOCV2
//
//  Created by Fragment System on 7/12/25.
//  Supports cross-page verse continuation for maximum content utilization
//

import Foundation
import SwiftUI

/// Represents a portion of a verse that can span across pages
public struct VerseFragment: Hashable, Identifiable, Codable {
    public let id = UUID()
    
    /// The verse reference this fragment belongs to
    let reference: VerseReference
    
    /// The text content of this fragment
    let textFragment: String
    
    /// True if this fragment starts at the beginning of the verse
    let isStartOfVerse: Bool
    
    /// True if this fragment ends at the end of the verse
    let isEndOfVerse: Bool
    
    /// The original full verse text (for reference)
    let fullVerseText: String
    
    /// Fragment sequence number within the verse (0-based)
    let sequenceNumber: Int
    
    /// Total number of fragments for this verse
    let totalFragments: Int
    
    /// Display text with continuation indicators
    var displayText: String {
        var text = textFragment
        
        // Add continuation indicators
        if !isStartOfVerse && !text.hasPrefix("...") {
            text = "..." + text
        }
        
        if !isEndOfVerse && !text.hasSuffix("...") {
            text = text + "..."
        }
        
        return text
    }
    
    /// Verse number for display
    var verseNumber: Int {
        reference.verse
    }
    
    /// True if this fragment is a continuation from previous page
    var isContinuation: Bool {
        !isStartOfVerse
    }
    
    /// True if this fragment continues to next page
    var hasMoreContent: Bool {
        !isEndOfVerse
    }
    
    public init(
        reference: VerseReference,
        textFragment: String,
        isStartOfVerse: Bool,
        isEndOfVerse: Bool,
        fullVerseText: String,
        sequenceNumber: Int,
        totalFragments: Int
    ) {
        self.reference = reference
        self.textFragment = textFragment
        self.isStartOfVerse = isStartOfVerse
        self.isEndOfVerse = isEndOfVerse
        self.fullVerseText = fullVerseText
        self.sequenceNumber = sequenceNumber
        self.totalFragments = totalFragments
    }
    
    // MARK: - Codable Implementation
    private enum CodingKeys: String, CodingKey {
        case reference, textFragment, isStartOfVerse, isEndOfVerse, 
             fullVerseText, sequenceNumber, totalFragments
    }
}

/// Collection of verse fragments that make up a page
public struct FragmentedPage: Identifiable, Codable, Hashable, Equatable {
    public let id = UUID()
    public let fragments: [VerseFragment]
    public let navTitle: String
    public let startVerse: VerseReference
    public let endVerse: VerseReference
    public let contentString: String
    public let measuredHeight: CGFloat
    public let availableHeight: CGFloat
    
    /// Combined attributed content for rendering (computed property)
    var content: AttributedString {
        AttributedString(contentString)
    }
    
    /// Verse keys for backwards compatibility
    var verseKeys: [VerseKey] {
        fragments.compactMap { fragment in
            VerseKey(
                book: fragment.reference.book,
                chapter: fragment.reference.chapter,
                verse: fragment.reference.verse
            )
        }
    }
    
    /// Unique verse references on this page
    var uniqueVerses: [VerseReference] {
        Array(Set(fragments.map { $0.reference })).sorted { first, second in
            if first.book != second.book {
                return first.book < second.book
            }
            if first.chapter != second.chapter {
                return first.chapter < second.chapter
            }
            return first.verse < second.verse
        }
    }
    
    /// Debug description
    var debugDescription: String {
        let fragmentCount = fragments.count
        let verseCount = uniqueVerses.count
        let heightRatio = measuredHeight / availableHeight
        return "Page: \(fragmentCount) fragments, \(verseCount) verses, \(Int(heightRatio * 100))% full"
    }
    
    /// Initializer for FragmentedPage
    init(
        fragments: [VerseFragment],
        navTitle: String,
        startVerse: VerseReference,
        endVerse: VerseReference,
        content: AttributedString,
        measuredHeight: CGFloat,
        availableHeight: CGFloat
    ) {
        self.fragments = fragments
        self.navTitle = navTitle
        self.startVerse = startVerse
        self.endVerse = endVerse
        self.contentString = String(content.characters)
        self.measuredHeight = measuredHeight
        self.availableHeight = availableHeight
    }
    
    // MARK: - Codable Implementation
    private enum CodingKeys: String, CodingKey {
        case fragments, navTitle, startVerse, endVerse, 
             contentString, measuredHeight, availableHeight
    }
}
