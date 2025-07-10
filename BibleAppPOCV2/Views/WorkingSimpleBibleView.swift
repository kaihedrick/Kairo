//
//  WorkingSimpleBibleView.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import SwiftUI

struct WorkingSimpleBibleView: View {
    @StateObject private var viewModel = SimpleBibleViewModel()
    @State private var selectedBook: ImprovedBibleModels.BookMetadata?
    @State private var selectedChapter: Int = 1
    @State private var showingBookSelector = false
    @State private var showingChapterSelector = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                contentView
            }
            .navigationTitle("Bible Reader")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadBooks()
            }
            .sheet(isPresented: $showingBookSelector) {
                bookSelectorView
            }
            .sheet(isPresented: $showingChapterSelector) {
                chapterSelectorView
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // Book selection
            Button(action: { showingBookSelector = true }) {
                HStack {
                    Text(selectedBook?.name ?? "Select Book")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            // Chapter navigation
            if selectedBook != nil {
                chapterNavigationView
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var chapterNavigationView: some View {
        HStack {
            // Previous
            Button(action: previousChapter) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(canGoPrevious ? .primary : .secondary)
            }
            .disabled(!canGoPrevious)
            
            Spacer()
            
            // Chapter title
            Button(action: { showingChapterSelector = true }) {
                Text(chapterTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            // Next
            Button(action: nextChapter) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(canGoNext ? .primary : .secondary)
            }
            .disabled(!canGoNext)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Content
    
    private var contentView: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let chapterContent = viewModel.chapterContent {
                chapterContentView(chapterContent)
            } else {
                placeholderView
            }
        }
    }
    
    private func chapterContentView(_ content: OptimizedBible.ChapterContent) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(content.verses, id: \.verse) { verse in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(verse.verse)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        
                        Text(verse.text)
                            .font(.body)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                }
            }
            .padding(.top)
        }
    }
    
    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Select a Book")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Book Selector
    
    private var bookSelectorView: some View {
        NavigationView {
            List(viewModel.filteredBooks, id: \.name) { book in
                Button(action: {
                    selectBook(book)
                    showingBookSelector = false
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("\(book.chapterCount) chapters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Select Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingBookSelector = false
                    }
                }
            }
        }
    }
    
    // MARK: - Chapter Selector
    
    private var chapterSelectorView: some View {
        NavigationView {
            if let book = selectedBook {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(1...book.chapterCount, id: \.self) { chapter in
                            Button(action: {
                                goToChapter(chapter)
                                showingChapterSelector = false
                            }) {
                                Text("\(chapter)")
                                    .font(.headline)
                                    .foregroundColor(chapter == selectedChapter ? .white : .primary)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        Circle()
                                            .fill(chapter == selectedChapter ? Color.accentColor : Color(.systemGray5))
                                    )
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle("\(book.name) Chapters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cancel") {
                            showingChapterSelector = false
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func selectBook(_ book: ImprovedBibleModels.BookMetadata) {
        selectedBook = book
        selectedChapter = 1
        loadChapter()
    }
    
    private func loadChapter() {
        guard let book = selectedBook else { return }
        
        Task {
            await viewModel.loadChapterAsync(book: book.name, chapter: selectedChapter)
        }
    }
    
    private func nextChapter() {
        guard canGoNext else { return }
        selectedChapter += 1
        loadChapter()
    }
    
    private func previousChapter() {
        guard canGoPrevious else { return }
        selectedChapter -= 1
        loadChapter()
    }
    
    private func goToChapter(_ chapter: Int) {
        guard let book = selectedBook, chapter > 0, chapter <= book.chapterCount else { return }
        selectedChapter = chapter
        loadChapter()
    }
    
    // MARK: - Computed Properties
    
    private var canGoNext: Bool {
        guard let book = selectedBook else { return false }
        return selectedChapter < book.chapterCount
    }
    
    private var canGoPrevious: Bool {
        return selectedChapter > 1
    }
    
    private var chapterTitle: String {
        guard let book = selectedBook else { return "" }
        return "\(book.name) \(selectedChapter)"
    }
}

#Preview {
    WorkingSimpleBibleView()
}
