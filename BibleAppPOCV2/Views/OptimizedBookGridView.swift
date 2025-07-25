// filepath: BibleAppPOCV2/Views/OptimizedBookGridView.swift
import SwiftUI

// MARK: - Scroll Tracking Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Optimized Book Grid View

struct OptimizedBookGridView: View {
    @StateObject private var viewModel = OptimizedBibleViewModel()
    @StateObject private var performanceMonitor = PerformanceMonitor()
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    // PERFORMANCE: Cache testament classifications
    @State private var cachedGroups: [String: [ImprovedBibleModels.BookMetadata]] = [:]
    @State private var lastMetadataHash: Int = 0
    
    // STABLE LAYOUT: Fixed grid configuration
    @State private var stableGridLayout: StableGridLayout = StableGridLayout()
    @State private var isLayoutCalculated = false
    @State private var lastKnownScreenSize: CGSize = .zero
    
    // SCROLL TRACKING: For dynamic header transition with enhanced glass effect
    @State private var scrollOffset: CGFloat = 0
    @State private var lastScrollOffset: CGFloat = 0
    @State private var isScrollingUp: Bool = false
    
    private var shouldShowGlassHeader: Bool {
        scrollOffset > 50 // Threshold for glass header activation
    }
    
    private var headerOpacity: Double {
        if shouldShowGlassHeader {
            let progress = max(0, min(1, (scrollOffset - 30) / 20)) // Smooth fade-in over 20pt
            return progress
        }
        return 0.0
    }
    
    // Enhanced scroll direction tracking for better glass effect behavior
    private var scrollDirection: ScrollDirection {
        if scrollOffset > lastScrollOffset {
            return .down
        } else if scrollOffset < lastScrollOffset {
            return .up
        }
        return .none
    }
    
    private enum ScrollDirection {
        case up, down, none
    }
    
    // Glass effect namespace for native iOS 26+ blur
    @Namespace private var glassNamespace
    
    // BOOK ABBREVIATIONS: Proper biblical abbreviations for readability - matching actual data names
    private let bookAbbreviations: [String: String] = [
        // Old Testament - matching exact data names
        "Genesis": "Gen", "Exodus": "Exod", "Leviticus": "Lev", "Numbers": "Num", "Deuteronomy": "Deut",
        "Joshua": "Josh", "Judges": "Judg", "Ruth": "Ruth", "I Samuel": "1Sam", "II Samuel": "2Sam",
        "I Kings": "1Kgs", "II Kings": "2Kgs", "I Chronicles": "1Chr", "II Chronicles": "2Chr",
        "Ezra": "Ezra", "Nehemiah": "Neh", "Esther": "Esth", "Job": "Job", "Psalms": "Ps",
        "Proverbs": "Prov", "Ecclesiastes": "Eccl", "Song of Solomon": "Song", "Isaiah": "Isa",
        "Jeremiah": "Jer", "Lamentations": "Lam", "Ezekiel": "Ezek", "Daniel": "Dan",
        "Hosea": "Hos", "Joel": "Joel", "Amos": "Amos", "Obadiah": "Obad", "Jonah": "Jon",
        "Micah": "Mic", "Nahum": "Nah", "Habakkuk": "Hab", "Zephaniah": "Zeph",
        "Haggai": "Hag", "Zechariah": "Zech", "Malachi": "Mal",
        
        // New Testament - matching exact data names
        "Matthew": "Matt", "Mark": "Mark", "Luke": "Luke", "John": "John", "Acts": "Acts",
        "Romans": "Rom", "I Corinthians": "1Cor", "II Corinthians": "2Cor", "Galatians": "Gal",
        "Ephesians": "Eph", "Philippians": "Phil", "Colossians": "Col", "I Thessalonians": "1Th",
        "II Thessalonians": "2Th", "I Timothy": "1Tim", "II Timothy": "2Tim", "Titus": "Tit",
        "Philemon": "Phm", "Hebrews": "Heb", "James": "Jas", "I Peter": "1Pet", "II Peter": "2Pet",
        "I John": "1Jn", "II John": "2Jn", "III John": "3Jn", "Jude": "Jude", "Revelation of John": "Rev"
    ]
    
    // PERFORMANCE: Testament name sets for faster lookups - using exact data names
    private let oldTestamentSet = Set([
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua",
        "Judges", "Ruth", "I Samuel", "II Samuel", "I Kings", "II Kings", "I Chronicles",
        "II Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
        "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations",
        "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah",
        "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi"
    ])
    
    private let newTestamentSet = Set([
        "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "I Corinthians",
        "II Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians",
        "I Thessalonians", "II Thessalonians", "I Timothy", "II Timothy", "Titus",
        "Philemon", "Hebrews", "James", "I Peter", "II Peter", "I John", "II John",
        "III John", "Jude", "Revelation of John"
    ])
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background that extends to screen edges - adapts to dark mode
                Color(UIColor.systemBackground).ignoresSafeArea()
                
                // Main content layer - ScrollView with book grid
                if viewModel.isInitializing {
                    initializationView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    mainContent
                }
                
                // Glassy header overlay (appears on scroll)
                glassyHeader
                
                // Bottom search overlay layer
                bottomSearchOverlay
            }
            .navigationBarHidden(true)  // Hide navigation bar since we have custom header
        }
        .onChange(of: isSearchActive) { _, _ in
            // Recalculate layout when search state changes
            isLayoutCalculated = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            withAnimation(.easeInOut(duration: 0.3)) {
                isSearchActive = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                if searchText.isEmpty {
                    isSearchActive = false
                }
            }
        }
        .task {
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
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { scrollGeometry in
                    Color.clear
                        .preference(key: ScrollOffsetPreferenceKey.self, value: scrollGeometry.frame(in: .named("scrollView")).minY)
                }
                .frame(height: 0)
                
                if !searchText.isEmpty && filteredBookGroups.isEmpty {
                    searchEmptyState
                        .padding(.top, 20)
                } else {
                    VStack(spacing: 16) {
                        // Default header inside ScrollView (visible before scroll threshold)
                        defaultHeader
                        
                        LazyVGrid(columns: stableGridLayout.gridItems, spacing: 12) {
                            ForEach(filteredBookGroups.keys.sorted(), id: \.self) { section in
                                Section(header: sectionHeader(section)) {
                                    ForEach(filteredBookGroups[section] ?? [], id: \.name) { bookMeta in
                                        NavigationLink {
                                            OptimizedChapterView(bookName: bookMeta.name, chapterCount: bookMeta.chapterCount)
                                        } label: {
                                            BookTileView(
                                                abbreviation: getBookAbbreviation(for: bookMeta.name),
                                                fullName: bookMeta.name
                                            )
                                            .frame(width: stableGridLayout.columnWidth, height: stableGridLayout.tileHeight)
                                            .glassTile(cornerRadius: 12, id: bookMeta.name, namespace: bookTileNamespace)
                                            .opacity(searchText.isEmpty ? 1.0 : (bookMeta.name.localizedCaseInsensitiveContains(searchText) ? 1.0 : 0.3))
                                            .scaleEffect(searchText.isEmpty ? 1.0 : (bookMeta.name.localizedCaseInsensitiveContains(searchText) ? 1.0 : 0.95))
                                            .animation(.easeInOut(duration: 0.25), value: searchText)
                                        }
                                        .disabled(!searchText.isEmpty && !bookMeta.name.localizedCaseInsensitiveContains(searchText))
                                        .buttonStyle(PlainButtonStyle()) // Ensure proper tap behavior
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, stableGridLayout.horizontalPadding)
                        .padding(.bottom, stableGridLayout.verticalPadding + 140)  // Extra padding for bottom search overlay
                    }
                    .padding(.top, stableGridLayout.verticalPadding)
                }
            }
            .coordinateSpace(name: "scrollView")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                let newOffset = -value
                
                // Enhanced scroll tracking with direction and smoothing
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1)) {
                    lastScrollOffset = scrollOffset
                    scrollOffset = newOffset
                    
                    // Track scroll direction for enhanced glass effect behavior
                    isScrollingUp = newOffset < lastScrollOffset
                }
                
                // Haptic feedback when glass header transitions
                let previouslyShowing = lastScrollOffset > 50
                let nowShowing = scrollOffset > 50
                
                if !previouslyShowing && nowShowing {
                    // Glass header just appeared
                    let impactFeedback = UIImpactFeedbackGenerator(style: .soft)
                    impactFeedback.impactOccurred(intensity: 0.4)
                } else if previouslyShowing && !nowShowing {
                    // Glass header just disappeared
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred(intensity: 0.6)
                }
            }
            .onAppear {
                // Layout calculation will be handled by parent view if needed
            }
            .onTapGesture {
                // Dismiss search when tapping main content
                if isSearchActive {
                    isSearchFocused = false
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSearchActive = false
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ScrollToTop"))) { _ in
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo("scrollTop", anchor: .top)
                }
            }
        }
    }
    
    // STABLE LAYOUT: Mobile-first grid structure with smaller tiles
    private struct StableGridLayout {
        let columnCount: Int = 4
        let columnWidth: CGFloat
        let tileHeight: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let interColumnSpacing: CGFloat = 8  // Reduced from 12 to 8 for more space
        let gridItems: [GridItem]
        
        // Search-specific padding
        let searchTopPadding: CGFloat
        let searchBottomPadding: CGFloat
        
        // Search field horizontal constraints
        let searchFieldHorizontalPadding: CGFloat
        let searchFieldMaxWidth: CGFloat
        
        init() {
            // Default values for initial state - optimized for mobile
            self.columnWidth = 70  // Reduced from 80
            self.tileHeight = 75   // Reduced from 90
            self.horizontalPadding = 12
            self.verticalPadding = 16
            self.searchTopPadding = 20
            self.searchBottomPadding = 32
            self.searchFieldHorizontalPadding = 16
            self.searchFieldMaxWidth = 320  // Reasonable max width for search field
            self.gridItems = Array(repeating: GridItem(.fixed(70), spacing: 8), count: 4)
        }
        
        init(geometry: GeometryProxy, isSearchActive: Bool = false) {
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let safeAreaInsets = geometry.safeAreaInsets
            
            // Detect orientation
            let isLandscape = screenWidth > screenHeight
            
            // Calculate available width accounting for safe areas
            let availableWidth = screenWidth - safeAreaInsets.leading - safeAreaInsets.trailing
            
            // Mobile-first approach: Reserve space for inter-column spacing first
            let totalSpacing = CGFloat(3) * interColumnSpacing
            
            // Calculate minimum horizontal padding (at least 12pt on each side)
            let minHorizontalPadding: CGFloat = 12
            let maxHorizontalPadding: CGFloat = 24
            
            // Calculate available width for tiles after minimum padding and spacing
            let availableForTiles = availableWidth - (minHorizontalPadding * 2) - totalSpacing
            
            // Calculate tile width, prioritizing smaller sizes for mobile
            let calculatedTileWidth = availableForTiles / 4
            
            // Mobile-first constraints: Cap tile size for better mobile experience
            let minTileWidth: CGFloat = 60   // Minimum for touch targets
            let maxTileWidth: CGFloat = 80   // Reduced from 120 to 80 for mobile optimization
            
            self.columnWidth = max(minTileWidth, min(maxTileWidth, calculatedTileWidth))
            self.tileHeight = columnWidth + 10  // Fixed height difference for consistent layout
            
            // Calculate actual horizontal padding after tile sizing
            let actualGridWidth = (columnWidth * 4) + totalSpacing
            self.horizontalPadding = max(minHorizontalPadding, min(maxHorizontalPadding, (availableWidth - actualGridWidth) / 2))
            
            self.verticalPadding = max(16, screenHeight * 0.02)  // Reduced vertical padding
            
            // Calculate search field horizontal constraints
            let baseSearchPadding = max(16, screenWidth * 0.04)  // Responsive to screen size
            let safeAreaAdjustment = max(safeAreaInsets.leading, safeAreaInsets.trailing)
            self.searchFieldHorizontalPadding = baseSearchPadding + safeAreaAdjustment
            
            // Calculate search field max width - never too wide, respects safe areas
            let maxSearchFieldWidth = min(
                availableWidth - (searchFieldHorizontalPadding * 2),
                isLandscape ? 600 : 400  // Landscape allows wider search field
            )
            self.searchFieldMaxWidth = max(280, maxSearchFieldWidth)
            
            // Calculate search-specific padding based on orientation and state
            if isLandscape {
                // Landscape: More conservative vertical padding
                self.searchTopPadding = max(16, screenHeight * 0.03) + (isSearchActive ? 8 : 0)
                self.searchBottomPadding = max(24, screenHeight * 0.035) + (isSearchActive ? 16 : 0)
            } else {
                // Portrait: More generous vertical padding
                self.searchTopPadding = max(20, screenHeight * 0.025) + (isSearchActive ? 8 : 0)
                self.searchBottomPadding = max(32, screenHeight * 0.04) + (isSearchActive ? 16 : 0)
            }
            
            // Create fixed-width grid items with calculated spacing
            self.gridItems = Array(repeating: GridItem(.fixed(columnWidth), spacing: interColumnSpacing), count: 4)
            
            // Debug logging to verify mobile-optimized calculations
#if DEBUG
            let totalGridWidth = (columnWidth * 4) + totalSpacing
            let totalWithPadding = totalGridWidth + (horizontalPadding * 2)
            print("� Mobile-Optimized Grid Layout:")
            print("  Screen Width: \(screenWidth)")
            print("  Available Width: \(availableWidth)")
            print("  Column Width: \(columnWidth) (capped at 80pt)")
            print("  Tile Height: \(tileHeight)")
            print("  Inter-Column Spacing: \(interColumnSpacing)")
            print("  Horizontal Padding: \(horizontalPadding)")
            print("  Total Grid Width: \(totalGridWidth)")
            print("  Total With Padding: \(totalWithPadding)")
            print("  Fits in Available: \(totalWithPadding <= availableWidth)")
            print("  Space Efficiency: \(Int((totalWithPadding/availableWidth)*100))%")
#endif
        }
    }
    
    // MARK: - Default Header (inside ScrollView)
    
    private var defaultHeader: some View {
        VStack(spacing: 0) {
            Text("📖 Select a Book")
                .font(.title2.bold())
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .padding(.horizontal, 20)
                .id("scrollTop") // Add ID for scroll-to-top
        }
        .opacity(shouldShowGlassHeader ? 0.0 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: shouldShowGlassHeader)
    }
    
    // MARK: - Glassy Header (pinned at top, appears on scroll)
    
    private var glassyHeader: some View {
        Group {
            if shouldShowGlassHeader {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Text("📖 Select a Book")
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, geometry.safeAreaInsets.top + 25)
                            .padding(.bottom, 16)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        // Native iOS glass effect using available APIs
                        RoundedRectangle(cornerRadius: 0)
                            .fill(.ultraThinMaterial)
                            .background(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 0)
                                    .fill(.ultraThinMaterial.opacity(0.3))
                                    .blendMode(.overlay)
                            )
                            .shadow(
                                color: Color.black.opacity(0.25),
                                radius: 4,
                                x: 0,
                                y: 1
                            )
                    )
                    .ignoresSafeArea(edges: .top)
                    .onTapGesture {
                        scrollToTop()
                    }
                }
                .opacity(headerOpacity)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
                .animation(.easeInOut(duration: 0.3), value: shouldShowGlassHeader)
                .zIndex(100)
            }
        }
    }
    
    // MARK: - Book Abbreviation Helper
    
    private func getBookAbbreviation(for bookName: String) -> String {
        return bookAbbreviations[bookName] ?? bookName
    }
    
    private var filteredBookGroups: [String: [ImprovedBibleModels.BookMetadata]] {
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
        var oldTestament = [ImprovedBibleModels.BookMetadata]()
        var newTestament = [ImprovedBibleModels.BookMetadata]()
        var unclassified = [ImprovedBibleModels.BookMetadata]()
        
        for book in metadata.books {
            if oldTestamentSet.contains(book.name) {
                oldTestament.append(book)
            } else if newTestamentSet.contains(book.name) {
                newTestament.append(book)
            } else {
                unclassified.append(book)
            }
        }
        
        // DEBUG: Log book classification results
#if DEBUG
        print("📚 Book Classification Results:")
        print("  Total books loaded: \(metadata.books.count)")
        print("  Old Testament: \(oldTestament.count) books")
        print("  New Testament: \(newTestament.count) books")
        print("  Unclassified: \(unclassified.count) books")
        
        if !unclassified.isEmpty {
            print("  ⚠️ Unclassified books:")
            for book in unclassified {
                print("    - \(book.name)")
            }
        }
        
        if let firstOT = oldTestament.first, let lastOT = oldTestament.last {
            print("  📖 OT: \(firstOT.name) ... \(lastOT.name)")
        }
        
        if let firstNT = newTestament.first, let lastNT = newTestament.last {
            print("  📖 NT: \(firstNT.name) ... \(lastNT.name)")
        }
        
        if newTestament.contains(where: { $0.name == "Revelation of John" }) {
            print("  ✅ Revelation of John is correctly classified in New Testament")
        } else {
            print("  ❌ Revelation of John is NOT found in New Testament")
        }
#endif
        
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
    
    private func sectionHeader(_ title: String) -> some View {
        let bookCount = filteredBookGroups[title]?.count ?? 0
        return Text("\(title) (\(bookCount) books)")
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
    
    // MARK: - Search Empty State
    
    private var searchEmptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No books found")
                    .font(.title2.weight(.medium))
                    .foregroundColor(.primary)
                
                Text("Try adjusting your search terms")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    searchText = ""
                    isSearchActive = false
                }
            }) {
                Text("Clear Search")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.blue.opacity(0.1))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
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
    // MARK: - Bottom Search Overlay with Liquid Glass Design
    
    @Namespace private var headerGlassNamespace // Dedicated namespace for floating header
    @Namespace private var bookTileNamespace // Dedicated namespace for book tiles glass effect

    private var bottomSearchOverlay: some View {
        GeometryReader { geometry in
            VStack {
                Spacer() // Push search to bottom
                
                HStack {
                    Spacer()
                    
                    // Search container with expand/collapse behavior
                    HStack(spacing: 12) {
                        // Search icon (always visible)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                            .animation(.easeInOut(duration: 0.2), value: isSearchActive)
                        
                        // Expanding search text field with enhanced liquid animation
                        if isSearchActive {
                            TextField("Search books", text: $searchText)
                                .font(.system(size: 16, weight: .medium))
                                .textFieldStyle(PlainTextFieldStyle())
                                .focused($isSearchFocused)
                                .onChange(of: searchText) { _, newValue in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1)) {
                                        isSearchActive = !newValue.isEmpty || isSearchFocused
                                    }
                                }
                                .onChange(of: isSearchFocused) { _, focused in
                                    if focused {
                                        // Enhanced haptic feedback when search becomes focused
                                        let impactFeedback = UIImpactFeedbackGenerator(style: .soft)
                                        impactFeedback.impactOccurred()
                                    }
                                    
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1)) {
                                        isSearchActive = focused || !searchText.isEmpty
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.95)),
                                    removal: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 1.05))
                                ))
                            
                            // Clear button (X) with enhanced liquid animation
                            Button(action: {
                                // Enhanced haptic feedback for clear action
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                
                                // Liquid-like spring animation for clearing
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1)) {
                                    searchText = ""
                                    isSearchActive = false
                                    isSearchFocused = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .scaleEffect(isSearchActive ? 1.0 : 0.8)
                                    .opacity(isSearchActive ? 1.0 : 0.7)
                            }
                            .transition(.scale.combined(with: .opacity))
                            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSearchActive)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .glassedEffect(shape: Capsule(), interactive: true)
                    .glassEffectUnionSafe(id: "searchArea", namespace: glassNamespace)
                    .frame(width: isSearchActive ? min(geometry.size.width - 40, 400) : 56, height: 56)
                    .scaleEffect(isSearchActive ? 1.0 : 0.95)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1), value: isSearchActive)
                    .onTapGesture {
                        if !isSearchActive {
                            // Enhanced haptic feedback for activation
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1)) {
                                isSearchActive = true
                                isSearchFocused = true
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20) + 14) // Safe area aware
            }
        }
        .allowsHitTesting(true)
        .onTapGesture {
            // Dismiss search when tapping outside the search container
            if isSearchActive && !isSearchFocused {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if searchText.isEmpty {
                        isSearchActive = false
                    }
                }
            }
        }
    }
    
    // MARK: - Scroll to Top Function
    
    private func scrollToTop() {
        // Post notification to trigger scroll to top
        NotificationCenter.default.post(name: Notification.Name("ScrollToTop"), object: nil)
    }
    
}
