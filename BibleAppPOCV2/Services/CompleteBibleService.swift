//
//  CompleteBibleService.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation
import SwiftUI

// MARK: - Type Aliases for Migration
enum BibleTypeAliases {
    // Create type aliases to bridge existing models with new improved models
    // This allows gradual migration without breaking existing code
    
    // Use existing types from current codebase
    typealias ExistingBibleMetadata = BibleMetadata  // From OptimizedBibleModels.swift
    typealias ExistingBookMetadata = BookMetadata    // From OptimizedBibleModels.swift
    typealias ExistingChapterContent = OptimizedBible.ChapterContent
    typealias ExistingVerseContent = OptimizedBible.Verse
}

// MARK: - Complete Service Protocols

/// Main Bible service protocol with all operations
protocol BibleServiceProtocol: Actor {
    func getMetadata() async -> ServiceResult<BibleMetadata>
    func loadChapter(book: String, chapter: Int) async -> ServiceResult<Chapter>
    func loadVerse(reference: VerseReference) async -> ServiceResult<Verse>
    func searchBooks(query: String) async -> ServiceResult<[BookMetadata]>
    func getNavigationContext(for reference: VerseReference) async -> ServiceResult<NavigationContext>
}

/// Page generation service protocol
protocol PageServiceProtocol: Actor {
    func generatePage(startingAt reference: VerseReference, pageSize: CGSize) async -> ServiceResult<PageContent>
    func getNextPage(from current: PageContent) async -> ServiceResult<PageContent?>
    func getPreviousPage(from current: PageContent) async -> ServiceResult<PageContent?>
}

/// Text formatting service protocol
protocol TextServiceProtocol {
    func formatVerse(_ verse: Verse, showChapterHeader: Bool, showBookTitle: Bool) -> AttributedString
    func measureText(_ text: AttributedString, containerSize: CGSize) -> CGSize
    func formatVerseRange(_ verses: [Verse]) -> AttributedString
}

// MARK: - Complete Bible Service Implementation

actor CompleteBibleService: BibleServiceProtocol {
    private let dataLoader: OptimizedBibleDataLoader
    private let cache: [String: Any] = [:]
    
    init(dataLoader: OptimizedBibleDataLoader = .shared) {
        self.dataLoader = dataLoader
    }
    
    func getMetadata() async -> ServiceResult<BibleMetadata> {
        do {
            await dataLoader.ensureMetadataLoaded()
            guard let metadata = await dataLoader.metadata else {
                return .failure(.dataNotFound("Bible metadata"))
            }
            return .success(metadata)
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }
    
    func loadChapter(book: String, chapter: Int) async -> ServiceResult<Chapter> {
        // Validate input
        guard !book.isEmpty, chapter > 0 else {
            return .failure(.invalidInput("Invalid book or chapter"))
        }
        
        guard let chapterContent = await dataLoader.loadChapterContent(book: book, chapter: chapter) else {
            return .failure(.dataNotFound("Chapter \(book) \(chapter)"))
        }
        
        // Convert to domain model
        let verses = chapterContent.verses.compactMap { verseContent in
            guard let reference = VerseReference(book: book, chapter: chapter, verse: verseContent.verse) else {
                return nil
            }
            return Verse(reference: reference, text: verseContent.text)
        }
        
        let domainChapter = Chapter(book: book, number: chapter, verses: verses)
        return .success(domainChapter)
    }
    
    func loadVerse(reference: VerseReference) async -> ServiceResult<Verse> {
        let chapterResult = await loadChapter(book: reference.book, chapter: reference.chapter)
        
        switch chapterResult {
        case .success(let chapter):
            if let verse = chapter.verses.first(where: { $0.reference.verse == reference.verse }) {
                return .success(verse)
            } else {
                return .failure(.dataNotFound("Verse \(reference.description)"))
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func searchBooks(query: String) async -> ServiceResult<[BookMetadata]> {
        guard !query.isEmpty else {
            return .failure(.invalidInput("Empty search query"))
        }
        
        let metadataResult = await getMetadata()
        switch metadataResult {
        case .success(let metadata):
            let filtered = metadata.books.filter { 
                $0.name.localizedCaseInsensitiveContains(query) 
            }
            return .success(filtered)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func getNavigationContext(for reference: VerseReference) async -> ServiceResult<NavigationContext> {
        let metadataResult = await getMetadata()
        
        switch metadataResult {
        case .success(let metadata):
            guard let bookMeta = metadata.books.first(where: { $0.name == reference.book }) else {
                return .failure(.dataNotFound("Book metadata for \(reference.book)"))
            }
            
            let chapterResult = await loadChapter(book: reference.book, chapter: reference.chapter)
            switch chapterResult {
            case .success(let chapter):
                let context = NavigationContext(
                    currentChapter: reference.chapter,
                    currentVerse: reference.verse,
                    totalChapters: bookMeta.chapterCount,
                    totalVerses: chapter.verseCount
                )
                return .success(context)
            case .failure(let error):
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
}

// MARK: - Text Formatting Service Implementation

class TextFormattingService: TextServiceProtocol {
    
    func formatVerse(_ verse: Verse, showChapterHeader: Bool = false, showBookTitle: Bool = false) -> AttributedString {
        var attributed = AttributedString()
        
        if showBookTitle {
            var bookAttr = AttributedString("\(verse.reference.book)\n\n")
            bookAttr.font = Typography.bookTitle
            bookAttr.foregroundColor = .primary
            attributed.append(bookAttr)
        }
        
        if showChapterHeader {
            var chapterAttr = AttributedString("\(verse.reference.chapter) ")
            chapterAttr.font = Typography.chapter
            chapterAttr.foregroundColor = .primary
            attributed.append(chapterAttr)
        }
        
        var verseNumberAttr = AttributedString("\(verse.reference.verse) ")
        verseNumberAttr.font = Typography.verseNumber
        verseNumberAttr.foregroundColor = .secondary
        
        var verseTextAttr = AttributedString(verse.text)
        verseTextAttr.font = Typography.body
        verseTextAttr.foregroundColor = .primary
        
        attributed.append(verseNumberAttr)
        attributed.append(verseTextAttr)
        
        return attributed
    }
    
    func measureText(_ text: AttributedString, containerSize: CGSize) -> CGSize {
        // Use existing TextMeasurer if available, or implement basic measurement
        return TextMeasurer.measure(text, size: containerSize)
    }
    
    func formatVerseRange(_ verses: [Verse]) -> AttributedString {
        var result = AttributedString()
        
        for (index, verse) in verses.enumerated() {
            let showChapterHeader = index == 0 || verse.reference.chapter != verses[index - 1].reference.chapter
            let formatted = formatVerse(verse, showChapterHeader: showChapterHeader)
            
            result.append(formatted)
            
            if index < verses.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        
        return result
    }
}
