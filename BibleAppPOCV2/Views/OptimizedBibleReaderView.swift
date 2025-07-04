import SwiftUI

struct OptimizedBibleReaderView: View {
    @StateObject private var pageGenerator: OnDemandPageGenerator
    @State private var currentPageInfo: String = ""
    @State private var showingPerformanceOverlay = false
    
    // For gesture handling
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    
    // Performance data
    @State private var performanceData: (hitRate: Double, size: Int) = (0.0, 0)
    
    // Add this state to store cache stats
    @State private var cacheStats: (hitRate: Double, size: Int) = (0.0, 0)
    
    let pageSize: CGSize
    let initialVerse: (book: String, chapter: Int, verse: Int)
    
    init(pageSize: CGSize, initialVerse: (book: String, chapter: Int, verse: Int)) {
        self.pageSize = pageSize
        self.initialVerse = initialVerse
        self._pageGenerator = StateObject(wrappedValue: OnDemandPageGenerator(pageSize: pageSize))
    }
    
    var body: some View {
        ZStack {
            // Background
            Image("parchment-bg")
                .resizable()
                .scaledToFill()
                .opacity(0.25)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Current location indicator with verse range
                if !currentPageInfo.isEmpty {
                    Text(currentPageInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity)
                }

                
                // Main content area
                ZStack {
                    if pageGenerator.isGenerating {
                        ProgressView("Loading page...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let currentPage = pageGenerator.currentPage {
                        pageView(currentPage.toOptimizedPageSlice())
                    } else {
                        ProgressView("Preparing content...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            }
            
            // Performance overlay (development only)
            if showingPerformanceOverlay {
                VStack {
                    Spacer()
                    performanceOverlayView
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Debug") {
                    showingPerformanceOverlay.toggle()
                }
            }
            #endif
        }
        .onAppear {
            Task {
                await pageGenerator.generatePage(startingAt: initialVerse)
                
                // Load initial performance stats
                let stats = await OptimizedBibleDataLoader.shared.getCacheStats()
                performanceData = stats
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            pageGenerator.handleMemoryPressure()
        }
    }
    
    private func pageView(_ page: OptimizedPageSlice) -> some View {
        Text(page.content)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .onChange(of: pageGenerator.currentPage?.startKey) { _ in
                if let newPage = pageGenerator.currentPage {
                    updateCurrentPageInfo(newPage.toOptimizedPageSlice())
                }
            }
            .onAppear {
                updateCurrentPageInfo(page)
            }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        dragOffset = .zero
                        handleSwipeGesture(value)
                    }
            )
    }
    
    private func handleSwipeGesture(_ value: DragGesture.Value) {
        let threshold: CGFloat = 50
        
        if value.translation.width > threshold {
            // Swipe right - previous page
            Task {
                await pageGenerator.generatePreviousPage()
            }
        } else if value.translation.width < -threshold {
            // Swipe left - next page
            Task {
                await pageGenerator.generateNextPage()
            }
        }
    }
    
    // Updated to show verse range
    private func updateCurrentPageInfo(_ page: OptimizedPageSlice) {
        let start = page.startVerse
        let end = page.endVerse
        
        if start.book == end.book {
            if start.chapter == end.chapter {
                if start.verse == end.verse {
                    // Single verse
                    currentPageInfo = "\(start.book) \(start.chapter):\(start.verse)"
                } else {
                    // Verse range in same chapter
                    currentPageInfo = "\(start.book) \(start.chapter):\(start.verse)-\(end.verse)"
                }
            } else {
                // Spans multiple chapters in same book
                currentPageInfo = "\(start.book) \(start.chapter):\(start.verse) - \(end.chapter):\(end.verse)"
            }
        } else {
            // Spans multiple books
            currentPageInfo = "\(start.book) \(start.chapter):\(start.verse) - \(end.book) \(end.chapter):\(end.verse)"
        }
    }
    
    private var performanceOverlayView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Monitor")
                .font(.headline)
            
            if let page = pageGenerator.currentPage {
                let slice = page.toOptimizedPageSlice()
                Text("Current page: \(slice.startVerse.description) to \(slice.endVerse.description)")
                Text("Verses in view: \(slice.verseKeys.count)")
            }
            
            Text("Memory: \(cacheStats.hitRate * 100, specifier: "%.1f")% hit rate")
        }
        .font(.caption)
        .padding()
        .background(.regularMaterial)
        .cornerRadius(10)
        .padding()
        .task {
            // Update stats periodically
            while true {
                do {
                    cacheStats = await OptimizedBibleDataLoader.shared.getCacheStats()
                    try await Task.sleep(nanoseconds: 1_000_000_000) // Update every 1 second
                } catch {
                    break
                }
            }
        }
    }
}