//
//  CleanBibleViewModel.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation
import SwiftUI

@MainActor
class CleanBibleViewModel: ObservableObject {
    @Published var books: [ImprovedBibleModels.BookMetadata] = []
    @Published var selectedBook: ImprovedBibleModels.BookMetadata?
    @Published var selectedChapter: Int = 1
    @Published var chapterContent: OptimizedBible.ChapterContent?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let service = CleanBibleService()
    
    // MARK: - Book Loading
    
    func loadBooks() async {
        isLoading = true
        errorMessage = nil
        
        let result = await service.getMetadataWithResult()
        switch result {
        case .success(let metadata):
            books = metadata.books
        case .failure(let error):
            errorMessage = error.errorDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Chapter Loading
    
    func loadChapter() async {
        guard let book = selectedBook else { return }
        
        isLoading = true
        errorMessage = nil
        
        let result = await service.loadChapterWithResult(book: book.name, chapter: selectedChapter)
        switch result {
        case .success(let content):
            chapterContent = content
        case .failure(let error):
            errorMessage = error.errorDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Book Selection
    
    func selectBook(_ book: ImprovedBibleModels.BookMetadata) {
        selectedBook = book
        selectedChapter = 1
        chapterContent = nil
        
        Task {
            await loadChapter()
        }
    }
    
    // MARK: - Chapter Navigation
    
    func nextChapter() {
        guard let book = selectedBook, selectedChapter < book.chapterCount else { return }
        selectedChapter += 1
        
        Task {
            await loadChapter()
        }
    }
    
    func previousChapter() {
        guard selectedChapter > 1 else { return }
        selectedChapter -= 1
        
        Task {
            await loadChapter()
        }
    }
    
    func goToChapter(_ chapter: Int) {
        guard let book = selectedBook, chapter > 0, chapter <= book.chapterCount else { return }
        selectedChapter = chapter
        
        Task {
            await loadChapter()
        }
    }
    
    // MARK: - Search
    
    func searchBooks(query: String) async -> [ImprovedBibleModels.BookMetadata] {
        return await service.searchBooks(query: query)
    }
    
    // MARK: - Computed Properties
    
    var canGoNext: Bool {
        guard let book = selectedBook else { return false }
        return selectedChapter < book.chapterCount
    }
    
    var canGoPrevious: Bool {
        return selectedChapter > 1
    }
    
    var chapterTitle: String {
        guard let book = selectedBook else { return "" }
        return "\(book.name) \(selectedChapter)"
    }
    
    var filteredBooks: [ImprovedBibleModels.BookMetadata] {
        return books // Can add filtering logic here if needed
    }
}

// MARK: - Environment Key

struct CleanBibleServiceKey: EnvironmentKey {
    static let defaultValue = CleanBibleService()
}

extension EnvironmentValues {
    var cleanBibleService: CleanBibleService {
        get { self[CleanBibleServiceKey.self] }
        set { self[CleanBibleServiceKey.self] = newValue }
    }
}
