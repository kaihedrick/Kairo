// filepath: BibleAppPOCV2/Models/UnifiedBibleModels.swift
//
//  UnifiedBibleModels.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//  Updated to alias ImprovedBibleModels to avoid duplication
//

import Foundation
import SwiftUI

/// Namespace providing aliases to the improved domain models.
/// This maintains backwards compatibility for components that still
/// reference `UnifiedBibleModels` while ensuring a single source of truth.
// public typealias VerseReference = ImprovedBibleModels.VerseReference
// public typealias Verse = ImprovedBibleModels.Verse
// public typealias Chapter = ImprovedBibleModels.Chapter
// public typealias Book = ImprovedBibleModels.Book
// public typealias BookMetadata = ImprovedBibleModels.BookMetadata
// public typealias BibleMetadata = ImprovedBibleModels.BibleMetadata
// public typealias ServiceResult<T> = ImprovedBibleModels.ServiceResult<T>
// If you need additional typealiases, add them here
enum UnifiedBibleModels {
    // Core domain models



    // Removed invalid alias: typealias Book = ImprovedBibleModels.Book
    // Removed invalid alias: typealias Chapter = ImprovedBibleModels.Chapter
    // Removed invalid alias: typealias Verse = ImprovedBibleModels.Verse
    // Removed invalid alias: typealias VerseReference = ImprovedBibleModels.VerseReference
    // Removed invalid alias: typealias VerseRange = ImprovedBibleModels.VerseRange

    // Metadata and navigation
    // Removed invalid alias: typealias BibleMetadata = ImprovedBibleModels.BibleMetadata
    // Removed invalid alias: typealias BookMetadata = ImprovedBibleModels.BookMetadata
    // Removed invalid alias: typealias NavigationContext = ImprovedBibleModels.NavigationContext

    // Service and error handling
    // Removed invalid alias: typealias ServiceResult<T> = ImprovedBibleModels.ServiceResult<T>
    // Removed invalid alias: typealias BibleError = ImprovedBibleModels.BibleError

    // Other shared types
    // Removed invalid alias: typealias BibleConstants = ImprovedBibleModels.BibleConstants
    // Removed invalid alias: typealias PageContent = ImprovedBibleModels.PageContent
}

// MARK: - Type Aliases for Backwards Compatibility
/// These aliases preserve external API names while the underlying
/// implementations come from `ImprovedBibleModels`.
enum UnifiedTypeAliases {
    // typealias UnifiedBibleMetadata = UnifiedBibleModels.BibleMetadata
    // typealias UnifiedBookMetadata  = UnifiedBibleModels.BookMetadata
    // typealias UnifiedChapter       = UnifiedBibleModels.Chapter
    // typealias UnifiedVerse         = UnifiedBibleModels.Verse
    // typealias UnifiedVerseReference = UnifiedBibleModels.VerseReference
    // typealias UnifiedBibleError    = UnifiedBibleModels.BibleError
    // typealias UnifiedServiceResult<T> = UnifiedBibleModels.ServiceResult<T>
}
