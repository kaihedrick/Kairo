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
    // Removed typealias Bible to resolve ambiguity
typealias LegacyBook           = Book
typealias LegacyChapter        = Chapter
public typealias Chapter           = Chapter
public typealias Verse             = Verse
public typealias VerseReference    = VerseReference
public typealias VerseRange        = VerseRange

    // Metadata and navigation
    typealias BibleMetadata     = BibleMetadata
    typealias BookMetadata      = BookMetadata
    typealias NavigationContext = NavigationContext

    // Service and error handling
    typealias ServiceResult<T> = ServiceResult<T>
    typealias BibleError       = BibleError

    // Other shared types
    typealias BibleConstants = BibleConstants
    typealias PageContent    = PageContent
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
