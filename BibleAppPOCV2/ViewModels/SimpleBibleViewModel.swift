//
//  SimpleBibleViewModel.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import Foundation
import SwiftUI

@MainActor
class SimpleBibleViewModel: ObservableObject {
    @Published var books: [OptimizedBibleModels.BookMetadata] = []
    @Published var selectedBook: OptimizedBibleModels.BookMetadata?
    @Published var selectedChapter: Int = 1
    @Published var chapterContent: OptimizedBible.ChapterContent?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let service = SimpleBibleService()
    
    // MARK: - Book Loading
    
    func loadBooks() async {
        isLoading = true
        errorMessage = nil
        
        do {
            if let metadata = await service.getMetadata() {
                books = metadata.books
            } else {
                errorMessage = "Could not load Bible books"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Chapter Loading
    
    func loadChapter() async {
        guard let book = selectedBook else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            chapterContent = await service.loadChapter(book: book.name, chapter: selectedChapter)
            if chapterContent == nil {
                errorMessage = "Could not load chapter \(selectedChapter) of \(book.name)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Book Selection
    
    func selectBook(_ book: OptimizedBibleModels.BookMetadata) {
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
    
    func searchBooks(query: String) async -> [OptimizedBibleModels.BookMetadata] {
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
}

// MARK: - Environment Key for Dependency Injection

struct SimpleBibleServiceKey: EnvironmentKey {
    static let defaultValue = SimpleBibleService()
}

extension EnvironmentValues {
    var simpleBibleService: SimpleBibleService {
        get { self[SimpleBibleServiceKey.self] }
        set { self[SimpleBibleServiceKey.self] = newValue }
    }
}
