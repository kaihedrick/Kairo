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
enum UnifiedBibleModels {
    // Core domain models
    typealias Bible          = ImprovedBibleModels.Bible
    typealias Book           = ImprovedBibleModels.Book
    typealias Chapter        = ImprovedBibleModels.Chapter
    typealias Verse          = ImprovedBibleModels.Verse
    typealias VerseReference = ImprovedBibleModels.VerseReference
    typealias VerseRange     = ImprovedBibleModels.VerseRange

    // Metadata and navigation
    typealias BibleMetadata     = ImprovedBibleModels.BibleMetadata
    typealias BookMetadata      = ImprovedBibleModels.BookMetadata
    typealias NavigationContext = ImprovedBibleModels.NavigationContext

    // Service and error handling
    typealias ServiceResult<T> = ImprovedBibleModels.ServiceResult<T>
    typealias BibleError       = ImprovedBibleModels.BibleError

    // Other shared types
    typealias BibleConstants = ImprovedBibleModels.BibleConstants
    typealias PageContent    = ImprovedBibleModels.PageContent
}

// MARK: - Type Aliases for Backwards Compatibility
/// These aliases preserve external API names while the underlying
/// implementations come from `ImprovedBibleModels`.
enum UnifiedTypeAliases {
    typealias UnifiedBibleMetadata = UnifiedBibleModels.BibleMetadata
    typealias UnifiedBookMetadata  = UnifiedBibleModels.BookMetadata
    typealias UnifiedChapter       = UnifiedBibleModels.Chapter
    typealias UnifiedVerse         = UnifiedBibleModels.Verse
    typealias UnifiedVerseReference = UnifiedBibleModels.VerseReference
    typealias UnifiedBibleError    = UnifiedBibleModels.BibleError
    typealias UnifiedServiceResult<T> = UnifiedBibleModels.ServiceResult<T>
}
