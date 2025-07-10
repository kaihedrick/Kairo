//
//  EnhancedBookGridView.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import SwiftUI

// MARK: - Enhanced Book Grid View (Working Version)

struct EnhancedBookGridView: View {
    @StateObject private var viewModel = OptimizedBibleViewModel()
    @State private var searchText = ""
    @State private var selectedTestament: TestamentFilter = .all
    @State private var showingErrorAlert = false
    
    // Grid configuration
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private let itemSize: CGFloat = 75
    
    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundView()
                
                if viewModel.isInitializing {
                    enhancedInitializationView
                } else if viewModel.hasEnhancedError {
                    enhancedErrorView
                } else {
                    enhancedMainContent
                }
            }
            .navigationTitle("📖 Bible")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search books...")
            .toolbar {
                enhancedToolbar
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("Retry") {
                    viewModel.retryInitializationEnhanced()
                }
                Button("Dismiss") {
                    viewModel.clearEnhancedError()
                }
            } message: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.enhancedErrorMessage)
                    if !viewModel.enhancedErrorRecovery.isEmpty {
                        Text(viewModel.enhancedErrorRecovery)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .task {
            await viewModel.initializeWithBetterErrorHandling()
        }
        .onChange(of: viewModel.hasEnhancedError) { _, hasError in
            showingErrorAlert = hasError
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            viewModel.handleMemoryWarning()
        }
    }
    
    // MARK: - Enhanced Subviews
    
    private var enhancedInitializationView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: viewModel.initializationProgress)
                    .stroke(Color.accentColor, lineWidth: 4)
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.initializationProgress)
            }
            
            VStack(spacing: 8) {
                Text("Loading Bible...")
                    .font(.headline.weight(.medium))
                
                Text("\(Int(viewModel.initializationProgress * 100))% Complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var enhancedErrorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Unable to Load Bible")
                    .font(.title2.weight(.semibold))
                
                Text(viewModel.enhancedErrorMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if !viewModel.enhancedErrorRecovery.isEmpty {
                    Text(viewModel.enhancedErrorRecovery)
                        .font(.caption)
                        .foregroundColor(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            
            HStack(spacing: 16) {
                Button("Retry") {
                    viewModel.retryInitializationEnhanced()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Dismiss") {
                    viewModel.clearEnhancedError()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var enhancedMainContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredBooks, id: \.name) { book in
                    NavigationLink {
                        EnhancedChapterView(bookName: book.name, chapterCount: book.chapterCount)
                    } label: {
                        EnhancedBookTileView(book: book)
                            .frame(width: itemSize, height: itemSize)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.initializeWithBetterErrorHandling()
        }
    }
    
    private var enhancedToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("Testament", selection: $selectedTestament) {
                    Label("All Books", systemImage: "book.fill")
                        .tag(TestamentFilter.all)
                    Label("Old Testament", systemImage: "book.closed.fill")
                        .tag(TestamentFilter.old)
                    Label("New Testament", systemImage: "cross.fill")
                        .tag(TestamentFilter.new)
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title3)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredBooks: [ImprovedBibleModels.BookMetadata] {
        let booksToFilter: [ImprovedBibleModels.BookMetadata]
        
        switch selectedTestament {
        case .all:
            booksToFilter = viewModel.metadata?.books ?? []
        case .old:
            booksToFilter = viewModel.oldTestamentBooksFiltered
        case .new:
            booksToFilter = viewModel.newTestamentBooksFiltered
        }
        
        if searchText.isEmpty {
            return booksToFilter
        } else {
            return viewModel.searchBooksWithValidation(query: searchText)
                .filter { booksToFilter.contains($0) }
        }
    }
}

// MARK: - Enhanced Book Tile View

struct EnhancedBookTileView: View {
    let book: ImprovedBibleModels.BookMetadata
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 6) {
            Text(String(book.name.prefix(3)))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text(book.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            
            Text("\(book.chapterCount) ch")
                .font(.system(size: 8, weight: .light))
                .foregroundColor(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.quaternary, lineWidth: 0.5)
                }
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { isPressing in
            isPressed = isPressing
        } perform: { }
    }
}

// MARK: - Enhanced Chapter View

struct EnhancedChapterView: View {
    let bookName: String
    let chapterCount: Int
    @StateObject private var chapterViewModel: EnhancedChapterViewModel
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    private let tileSize: CGFloat = 50
    
    init(bookName: String, chapterCount: Int) {
        self.bookName = bookName
        self.chapterCount = chapterCount
        self._chapterViewModel = StateObject(wrappedValue: EnhancedChapterViewModel(bookName: bookName, chapterNumber: 1))
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...chapterCount, id: \.self) { chapter in
                    NavigationLink {
                        EnhancedVerseView(bookName: bookName, chapterNumber: chapter)
                    } label: {
                        Text("\(chapter)")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(width: tileSize, height: tileSize)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.quaternary, lineWidth: 0.5)
                            )
                    }
                }
            }
            .padding()
        }
        .navigationTitle(bookName)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Enhanced Verse View Placeholder

struct EnhancedVerseView: View {
    let bookName: String
    let chapterNumber: Int
    
    var body: some View {
        Text("Enhanced Verse View for \(bookName) \(chapterNumber)")
            .navigationTitle("\(bookName) \(chapterNumber)")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Supporting Types

enum TestamentFilter: String, CaseIterable {
    case all = "All"
    case old = "Old Testament"
    case new = "New Testament"
}
