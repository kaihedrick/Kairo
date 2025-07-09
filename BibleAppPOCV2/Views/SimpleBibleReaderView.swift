//
//  SimpleBibleReaderView.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import SwiftUI

struct SimpleBibleReaderView: View {
    @StateObject private var viewModel = SimpleBibleViewModel()
    @State private var showingBookSelector = false
    @State private var showingChapterSelector = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with navigation
                headerView
                
                // Main content
                contentView
            }
            .navigationTitle("Bible Reader")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadBooks()
            }
            .sheet(isPresented: $showingBookSelector) {
                bookSelectorSheet
            }
            .sheet(isPresented: $showingChapterSelector) {
                chapterSelectorSheet
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // Book selection button
            Button(action: { showingBookSelector = true }) {
                HStack {
                    Text(viewModel.selectedBook?.name ?? "Select Book")
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
            if viewModel.selectedBook != nil {
                chapterNavigationView
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(radius: 1)
    }
    
    private var chapterNavigationView: some View {
        HStack {
            // Previous chapter button
            Button(action: { viewModel.previousChapter() }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(viewModel.canGoPrevious ? .primary : .secondary)
            }
            .disabled(!viewModel.canGoPrevious)
            
            Spacer()
            
            // Chapter selector
            Button(action: { showingChapterSelector = true }) {
                Text(viewModel.chapterTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Next chapter button
            Button(action: { viewModel.nextChapter() }) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(viewModel.canGoNext ? .primary : .secondary)
            }
            .disabled(!viewModel.canGoNext)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                errorView(errorMessage)
            } else if let chapterContent = viewModel.chapterContent {
                chapterView(chapterContent)
            } else {
                placeholderView
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                Task {
                    if viewModel.selectedBook != nil {
                        await viewModel.loadChapter()
                    } else {
                        await viewModel.loadBooks()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func chapterView(_ content: OptimizedBible.ChapterContent) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(content.verses, id: \.verse) { verse in
                    HStack(alignment: .top, spacing: 8) {
                        // Verse number
                        Text("\(verse.verse)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        
                        // Verse text
                        Text(verse.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 16)
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
            
            Text("Choose a book from the Bible to start reading")
                .font(.subheadline)
                .foregroundColor(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Book Selector Sheet

extension SimpleBibleReaderView {
    private var bookSelectorSheet: some View {
        NavigationView {
            List(viewModel.books, id: \.name) { book in
                Button(action: {
                    viewModel.selectBook(book)
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
                    .contentShape(Rectangle())
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
        .sheet(isPresented: $showingChapterSelector) {
            chapterSelectorSheet
        }
        NavigationView {
            if let book = viewModel.selectedBook {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(1...book.chapterCount, id: \.self) { chapter in
                            Button(action: {
                                viewModel.goToChapter(chapter)
                                showingChapterSelector = false
                            }) {
                                Text("\(chapter)")
                                    .font(.headline)
                                    .foregroundColor(chapter == viewModel.selectedChapter ? .white : .primary)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        Circle()
                                            .fill(chapter == viewModel.selectedChapter ? Color.accentColor : Color(.systemGray5))
                                    )
                            }
                            .buttonStyle(.plain)
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
}

#Preview {
    SimpleBibleReaderView()
}
