import SwiftUI  // Add this import statement

// MARK: - Optimized Book Grid View

struct OptimizedBookGridView: View {
    @StateObject private var viewModel = OptimizedBibleViewModel()
    @StateObject private var performanceMonitor = PerformanceMonitor()
    @State private var searchText = ""
    
    // PERFORMANCE: Cache testament classifications
    @State private var cachedGroups: [String: [BookMetadata]] = [:]
    @State private var lastMetadataHash: Int = 0
    
    // PERFORMANCE: Lazy grid configuration for smooth scrolling
// To:
private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
private let gridItemSize: CGFloat = 70

    
    // PERFORMANCE: Testament name sets for faster lookups
    private let oldTestamentSet = Set([
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua",
        "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles",
        "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
        "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations",
        "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah",
        "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi"
    ])
    
    private let newTestamentSet = Set([
        "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians",
        "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians",
        "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus",
        "Philemon", "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John",
        "3 John", "Jude", "Revelation"
    ])

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
        }
        .task {  // Use .task instead of direct access
            await loadMetadata()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            viewModel.handleMemoryWarning()
        }
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
    
    private var mainContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredBookGroups.keys.sorted(), id: \.self) { section in
                    Section(header: sectionHeader(section)) {
                        ForEach(filteredBookGroups[section] ?? [], id: \.name) { bookMeta in
                            NavigationLink {
                                OptimizedChapterView(bookName: bookMeta.name, chapterCount: bookMeta.chapterCount)
                            } label: {
                                BookTileView(
                                    abbreviation: String(bookMeta.name.prefix(3)),
                                    fullName: bookMeta.name
                                )
                                .frame(width: gridItemSize, height: gridItemSize)   // Instead of height: 80

                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical)
        }
        .searchable(text: $searchText, prompt: "Search books")
        .navigationTitle("📖 Select a Book")
    }
    
    private var filteredBookGroups: [String: [BookMetadata]] {
        guard let metadata = viewModel.metadata else { return [:] }
        
        // Check if metadata has changed
        let currentHash = metadata.books.hashValue
        if currentHash == lastMetadataHash && !cachedGroups.isEmpty {
            // Use cached groups if metadata hasn't changed
            if searchText.isEmpty {
                return cachedGroups
            } else {
                // Apply search filter on cached data
                return cachedGroups.compactMapValues { books in
                    let filtered = books.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                    return filtered.isEmpty ? nil : filtered
                }
            }
        }
        
        // PERFORMANCE: Single-pass classification for efficiency
        var oldTestament = [BookMetadata]()
        var newTestament = [BookMetadata]()
        
        for book in metadata.books {
            if oldTestamentSet.contains(book.name) {
                oldTestament.append(book)
            } else if newTestamentSet.contains(book.name) {
                newTestament.append(book)
            }
        }
        
        // Cache the results
        Task { @MainActor in
            self.cachedGroups = [
                "Old Testament": oldTestament,
                "New Testament": newTestament
            ]
            self.lastMetadataHash = currentHash
        }
        
        // OPTIMIZATION: Skip filtering when search is empty
        if searchText.isEmpty {
            return cachedGroups
        }
        
        // Apply search filter
        return cachedGroups.compactMapValues { books in
            let filtered = books.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            return filtered.isEmpty ? nil : filtered
        }
    }
    
    private var backgroundView: some View {
        Image("parchment-bg")
            .resizable()
            .scaledToFill()
            .opacity(0.25)
            .ignoresSafeArea()
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
    
    // Memory warning handling
    func handleMemoryWarning() {
        Task { @MainActor in
            // Update state properly
            self.cachedGroups = [:]
            self.lastMetadataHash = 0
        }
    }
    
    // Add this function to handle async metadata loading
    @MainActor private func loadMetadata() async {
        // This function safely accesses actor-isolated properties
        // and will be called when the view appears
    }
}