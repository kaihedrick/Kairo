//
//  ImprovedBookGridView.swift
//  BibleAppPOCV2
//
//  Created by Architecture Migration on 7/9/25.
//

import SwiftUI

// MARK: - Improved Book Grid View with Better Architecture

struct ImprovedBookGridView: View {
    @StateObject private var viewModel: OptimizedBibleViewModel
    @State private var searchText = ""
    @State private var selectedTestament: Testament = .all
    
    // Dependency injection through environment
    @Environment(\.diContainer) private var diContainer
    
    // Better constants management
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    private let gridItemSize: CGFloat = 70
    
    init(viewModel: OptimizedBibleViewModel? = nil) {
        // Allow dependency injection while maintaining backward compatibility
        self._viewModel = StateObject(wrappedValue: viewModel ?? OptimizedBibleViewModel())
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView
                
                if viewModel.isInitializing {
                    initializationView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    mainContent
                }
            }
            .navigationTitle("📖 Select a Book")
            .searchable(text: $searchText, prompt: "Search books")
            .toolbar {
                testamentPicker
            }
        }
        .task {
            // Better async initialization
            await viewModel.initializeDataImproved()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            handleMemoryWarning()
        }
    }
    
    // MARK: - Subviews
    
    private var mainContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(filteredBookGroups.keys.sorted(), id: \.self) { section in
                    Section(header: sectionHeader(section)) {
                        ForEach(filteredBookGroups[section] ?? [], id: \.name) { bookMeta in
                            NavigationLink {
                                ImprovedChapterView(
                                    bookName: bookMeta.name,
                                    chapterCount: bookMeta.chapterCount
                                )
                            } label: {
                                ImprovedBookTileView(
                                    abbreviation: bookMeta.abbreviation,
                                    fullName: bookMeta.name
                                )
                                .frame(width: gridItemSize, height: gridItemSize)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical)
        }
    }
    
    private var testamentPicker: some View {
        Picker("Testament", selection: $selectedTestament) {
            Text("All").tag(Testament.all)
            Text("Old").tag(Testament.old)
            Text("New").tag(Testament.new)
        }
        .pickerStyle(.segmented)
    }
    
    private var backgroundView: some View {
        BackgroundView()
    }
    
    private var initializationView: some View {
        VStack(spacing: 20) {
            ProgressView(value: viewModel.initializationProgress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(width: 200)
            
            Text("Loading Bible...")
                .font(.headline)
            
            Text("\(Int(viewModel.initializationProgress * 100))% Complete")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text("Initialization Failed")
                .font(.headline)
            
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                viewModel.retryInitialization()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
    
    // MARK: - Computed Properties
    
    private var filteredBookGroups: [String: [BookMetadata]] {
        guard let metadata = viewModel.metadata else { return [:] }
        
        let books = metadata.books
        
        // Filter by testament
        let testamentFilteredBooks: [BookMetadata]
        switch selectedTestament {
        case .all:
            testamentFilteredBooks = books
        case .old:
            testamentFilteredBooks = metadata.oldTestamentBooks
        case .new:
            testamentFilteredBooks = metadata.newTestamentBooks
        }
        
        // Filter by search text
        let searchFilteredBooks = searchText.isEmpty ? 
            testamentFilteredBooks : 
            testamentFilteredBooks.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        
        // Group by testament
        return Dictionary(grouping: searchFilteredBooks) { book in
            if BibleConstants.oldTestament.contains(book.name) {
                return "Old Testament"
            } else {
                return "New Testament"
            }
        }
    }
    
    // MARK: - Methods
    
    private func handleMemoryWarning() {
        Task { @MainActor in
            viewModel.handleMemoryWarning()
        }
    }
}

// MARK: - Supporting Types

enum Testament: CaseIterable {
    case all, old, new
}

// MARK: - Improved Book Tile View

struct ImprovedBookTileView: View {
    let abbreviation: String
    let fullName: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(abbreviation)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text(fullName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Improved Chapter View Placeholder

struct ImprovedChapterView: View {
    let bookName: String
    let chapterCount: Int
    
    var body: some View {
        Text("Improved Chapter View for \(bookName)")
            .navigationTitle(bookName)
    }
}
