//
//  ModernBibleViewModel.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation
import SwiftUI

// MARK: - Modern Bible View Model with Full DI

@MainActor
final class ModernBibleViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var metadata: BibleMetadata?
    @Published var isInitializing = true
    @Published var initializationProgress: Double = 0.0
    @Published var lastError: BibleError?
    @Published var isLoading = false
    
    // MARK: - Services (Dependency Injection)
    private let bibleService: BibleServiceProtocol
    private let textService: TextServiceProtocol
    
    // MARK: - Initialization
    init(bibleService: BibleServiceProtocol, textService: TextServiceProtocol) {
        self.bibleService = bibleService
        self.textService = textService
        
        Task {
            await initialize()
        }
    }
    
    // Convenience initializer for backward compatibility
    convenience init() {
        let service = CompleteBibleService()
        let textService = TextFormattingService()
        self.init(bibleService: service, textService: textService)
    }
    
    // MARK: - Public Methods
    
    func initialize() async {
        isInitializing = true
        lastError = nil
        initializationProgress = 0.0
        
        initializationProgress = 0.2
        
        let result = await bibleService.getMetadata()
        switch result {
        case .success(let loadedMetadata):
            initializationProgress = 0.8
            metadata = loadedMetadata
            initializationProgress = 1.0
            
            // Brief delay to show completion
            try? await Task.sleep(nanoseconds: 300_000_000)
            isInitializing = false
            
        case .failure(let error):
            lastError = error
            isInitializing = false
        }
    }
    
    func searchBooks(query: String) async -> [BookMetadata] {
        guard !query.isEmpty else { return metadata?.books ?? [] }
        
        isLoading = true
        let result = await bibleService.searchBooks(query: query)
        isLoading = false
        
        switch result {
        case .success(let books):
            return books
        case .failure(let error):
            lastError = error
            return []
        }
    }
    
    func loadChapter(book: String, chapter: Int) async -> Chapter? {
        isLoading = true
        let result = await bibleService.loadChapter(book: book, chapter: chapter)
        isLoading = false
        
        switch result {
        case .success(let chapterData):
            return chapterData
        case .failure(let error):
            lastError = error
            return nil
        }
    }
    
    func getNavigationContext(for reference: VerseReference) async -> NavigationContext? {
        let result = await bibleService.getNavigationContext(for: reference)
        
        switch result {
        case .success(let context):
            return context
        case .failure(let error):
            lastError = error
            return nil
        }
    }
    
    func retryInitialization() {
        Task {
            await initialize()
        }
    }
    
    func clearError() {
        lastError = nil
    }
    
    // MARK: - Computed Properties
    
    var hasError: Bool {
        lastError != nil
    }
    
    var errorMessage: String {
        lastError?.localizedDescription ?? ""
    }
    
    var errorRecoverySuggestion: String {
        lastError?.recoverySuggestion ?? ""
    }
    
    var oldTestamentBooks: [BookMetadata] {
        metadata?.oldTestamentBooks ?? []
    }
    
    var newTestamentBooks: [BookMetadata] {
        metadata?.newTestamentBooks ?? []
    }
}

// MARK: - Chapter View Model

@MainActor
final class ModernChapterViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var chapter: Chapter?
    @Published var isLoading = true
    @Published var lastError: BibleError?
    @Published var navigationContext: NavigationContext?
    
    // MARK: - Properties
    let bookName: String
    let chapterNumber: Int
    
    // MARK: - Services
    private let bibleService: BibleServiceProtocol
    
    // MARK: - Initialization
    init(bookName: String, chapterNumber: Int, bibleService: BibleServiceProtocol) {
        self.bookName = bookName
        self.chapterNumber = chapterNumber
        self.bibleService = bibleService
    }
    
    convenience init(bookName: String, chapterNumber: Int) {
        let service = CompleteBibleService()
        self.init(bookName: bookName, chapterNumber: chapterNumber, bibleService: service)
    }
    
    // MARK: - Public Methods
    
    func loadChapter() async {
        isLoading = true
        lastError = nil
        
        let result = await bibleService.loadChapter(book: bookName, chapter: chapterNumber)
        
        switch result {
        case .success(let chapterData):
            chapter = chapterData
            
            // Load navigation context
            if let firstVerse = chapterData.verses.first {
                let contextResult = await bibleService.getNavigationContext(for: firstVerse.reference)
                if case .success(let context) = contextResult {
                    navigationContext = context
                }
            }
            
        case .failure(let error):
            lastError = error
        }
        
        isLoading = false
    }
    
    func retryLoading() {
        Task {
            await loadChapter()
        }
    }
    
    func clearError() {
        lastError = nil
    }
    
    // MARK: - Computed Properties
    
    var hasError: Bool {
        lastError != nil
    }
    
    var errorMessage: String {
        lastError?.localizedDescription ?? ""
    }
    
    var verseCount: Int {
        chapter?.verseCount ?? 0
    }
    
    var isFirstChapter: Bool {
        navigationContext?.isFirstChapter ?? false
    }
    
    var isLastChapter: Bool {
        navigationContext?.isLastChapter ?? false
    }
}

// MARK: - Reader View Model

@MainActor
final class ModernReaderViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentPage: PageContent?
    @Published var isGenerating = false
    @Published var lastError: BibleError?
    @Published var navigationContext: NavigationContext?
    
    // MARK: - Properties
    private var pageSize: CGSize
    private let bibleService: BibleServiceProtocol
    private let textService: TextServiceProtocol
    
    // MARK: - Initialization
    init(pageSize: CGSize, bibleService: BibleServiceProtocol, textService: TextServiceProtocol) {
        self.pageSize = pageSize
        self.bibleService = bibleService
        self.textService = textService
    }
    
    convenience init(pageSize: CGSize) {
        let service = CompleteBibleService()
        let textService = TextFormattingService()
        self.init(pageSize: pageSize, bibleService: service, textService: textService)
    }
    
    // MARK: - Public Methods
    
    func generatePage(startingAt reference: VerseReference) async {
        isGenerating = true
        lastError = nil
        
        // Load the chapter containing this verse
        let chapterResult = await bibleService.loadChapter(book: reference.book, chapter: reference.chapter)
        
        switch chapterResult {
        case .success(let chapter):
            // Find verses for this page
            guard let startIndex = chapter.verses.firstIndex(where: { $0.reference.verse == reference.verse }) else {
                lastError = .dataNotFound("Verse \(reference.description)")
                isGenerating = false
                return
            }
            
            // For now, show one verse per page (can be enhanced for multi-verse pages)
            let verse = chapter.verses[startIndex]
            let attributedText = textService.formatVerse(verse, showChapterHeader: true)
            
            currentPage = PageContent(
                attributedText: attributedText,
                startReference: verse.reference,
                endReference: verse.reference,
                references: [verse.reference]
            )
            
            // Load navigation context
            let contextResult = await bibleService.getNavigationContext(for: reference)
            if case .success(let context) = contextResult {
                navigationContext = context
            }
            
        case .failure(let error):
            lastError = error
        }
        
        isGenerating = false
    }
    
    func updatePageSize(_ newSize: CGSize) {
        pageSize = newSize
        // Regenerate current page if needed
        if let currentPage = currentPage {
            Task {
                await generatePage(startingAt: currentPage.startReference)
            }
        }
    }
    
    func clearError() {
        lastError = nil
    }
    
    // MARK: - Computed Properties
    
    var hasError: Bool {
        lastError != nil
    }
    
    var errorMessage: String {
        lastError?.localizedDescription ?? ""
    }
}
