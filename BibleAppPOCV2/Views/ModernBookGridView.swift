//
//  ModernBookGridView.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import SwiftUI

// MARK: - Modern Book Grid View with Complete Architecture

struct ModernBookGridView: View {
    @StateObject private var viewModel: ModernBibleViewModel
    @State private var searchText = ""
    @State private var selectedTestament: Testament = .all
    @State private var showingErrorAlert = false
    
    // Grid configuration
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private let itemSize: CGFloat = 80
    
    // MARK: - Initialization
    init(viewModel: ModernBibleViewModel? = nil) {
        self._viewModel = StateObject(wrappedValue: viewModel ?? ModernBibleViewModel())
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView
                
                if viewModel.isInitializing {
                    initializationView
                } else if viewModel.hasError {
                    errorView
                } else {
                    mainContent
                }
            }
            .navigationTitle("📖 Bible")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search books...")
            .toolbar {
                toolbarContent
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("Retry") {
                    viewModel.retryInitialization()
                }
                Button("Dismiss") {
                    viewModel.clearError()
                }
            } message: {
                VStack(alignment: .leading) {
                    Text(viewModel.errorMessage)
                    if !viewModel.errorRecoverySuggestion.isEmpty {
                        Text(viewModel.errorRecoverySuggestion)
                            .font(.caption)
                    }
                }
            }
        }
        .onChange(of: viewModel.hasError) { _, hasError in
            showingErrorAlert = hasError
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            handleMemoryWarning()
        }
    }
    
    // MARK: - Subviews
    
    private var backgroundView: some View {
        BackgroundView()
    }
    
    private var initializationView: some View {
        VStack(spacing: 24) {
            // Modern loading animation
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: viewModel.initializationProgress)
                    .stroke(Color.accentColor, lineWidth: 4)
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: viewModel.initializationProgress)
            }
            
            VStack(spacing: 8) {
                Text("Loading Bible...")
                    .font(.headline)
                
                Text("\(Int(viewModel.initializationProgress * 100))% Complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Unable to Load Bible")
                    .font(.title2.weight(.semibold))
                
                Text(viewModel.errorMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if !viewModel.errorRecoverySuggestion.isEmpty {
                    Text(viewModel.errorRecoverySuggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            HStack(spacing: 16) {
                Button("Retry") {
                    viewModel.retryInitialization()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Dismiss") {
                    viewModel.clearError()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var mainContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredBooks, id: \.name) { book in
                    NavigationLink {
                        ModernChapterView(bookName: book.name, chapterCount: book.chapterCount)
                    } label: {
                        ModernBookTileView(book: book)
                            .frame(width: itemSize, height: itemSize)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.initialize()
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("Testament", selection: $selectedTestament) {
                    Label("All Books", systemImage: "book.fill")
                        .tag(Testament.all)
                    Label("Old Testament", systemImage: "book.closed.fill")
                        .tag(Testament.old)
                    Label("New Testament", systemImage: "cross.fill")
                        .tag(Testament.new)
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
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
            booksToFilter = viewModel.oldTestamentBooks
        case .new:
            booksToFilter = viewModel.newTestamentBooks
        }
        
        if searchText.isEmpty {
            return booksToFilter
        } else {
            return booksToFilter.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) 
            }
        }
    }
    
    // MARK: - Methods
    
    private func handleMemoryWarning() {
        // Handle memory pressure
        Task { @MainActor in
            // Could clear caches, reduce data, etc.
        }
    }
}

// MARK: - Modern Book Tile View

struct ModernBookTileView: View {
    let book: ImprovedBibleModels.BookMetadata
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 6) {
            // Book abbreviation
            Text(book.abbreviation)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // Full book name
            Text(book.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            
            // Chapter count
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

// MARK: - Modern Chapter View Placeholder

struct ModernChapterView: View {
    let bookName: String
    let chapterCount: Int
    @StateObject private var viewModel: ModernChapterViewModel
    
    init(bookName: String, chapterCount: Int) {
        self.bookName = bookName
        self.chapterCount = chapterCount
        self._viewModel = StateObject(wrappedValue: ModernChapterViewModel(bookName: bookName, chapterNumber: 1))
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(1...chapterCount, id: \.self) { chapter in
                    NavigationLink {
                        ModernReaderView(
                            bookName: bookName, 
                            chapter: chapter
                        )
                    } label: {
                        Text("\(chapter)")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(width: 50, height: 50)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding()
        }
        .navigationTitle(bookName)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Modern Reader View Placeholder

struct ModernReaderView: View {
    let bookName: String
    let chapter: Int
    
    var body: some View {
        Text("Modern Reader for \(bookName) \(chapter)")
            .navigationTitle("\(bookName) \(chapter)")
            .navigationBarTitleDisplayMode(.inline)
    }
}
