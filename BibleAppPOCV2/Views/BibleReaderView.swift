
import SwiftUI
import CoreGraphics
struct BibleReaderView: View {
    @StateObject private var pageGenerator: OnDemandPageGenerator
    @State private var currentPageInfo: String = ""
    @State private var showingPerformanceOverlay = false
    @State private var cacheStats: (hitRate: Double, size: Int) = (0.0, 0)
    
    // LLM Integration State
    @State private var selectedVerse: VerseKey? = nil
    @State private var showSummaryPopup: Bool = false
    @StateObject private var summaryViewModel = VerseSummaryViewModel()

    // For gesture handling
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    let pageSize: CGSize
    let initialVerse: (book: String, chapter: Int, verse: Int)

    init(pageSize: CGSize, initialVerse: (book: String, chapter: Int, verse: Int)) {
        self.pageSize = pageSize
        self.initialVerse = initialVerse
        self._pageGenerator = StateObject(wrappedValue: OnDemandPageGenerator(pageSize: pageSize))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !currentPageInfo.isEmpty {
                        Text(currentPageInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                    }

                    ZStack {
                        if pageGenerator.isGenerating {
                            ProgressView("Loading page...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let currentPage = pageGenerator.currentPage {
                            pageView(currentPage, size: size)
                        } else if let error = pageGenerator.lastError {
                            errorView(error)
                        } else {
                            ProgressView("Preparing content...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    if pageGenerator.currentPage == nil {
                        pageGenerator.updatePageSize(size)
                        await pageGenerator.generatePage(startingAt: initialVerse)
                    }
                }
                .onChange(of: size) { _, newSize in
                    pageGenerator.updatePageSize(newSize)
                    let start = pageGenerator.currentPage?.startVerse ?? VerseKey(book: initialVerse.book, chapter: initialVerse.chapter, verse: initialVerse.verse)
                    Task { await pageGenerator.generatePage(startingAt: (start.book, start.chapter, start.verse)) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    pageGenerator.handleMemoryPressure()
                }
                
                // LLM Summary Popup Overlay
                if let selectedVerse = selectedVerse, showSummaryPopup {
                    VerseSummaryPopupView(
                        verseKey: selectedVerse,
                        isVisible: $showSummaryPopup
                    )
                    .environmentObject(summaryViewModel)
                    .animation(.easeInOut(duration: 0.3), value: showSummaryPopup)
                }
            }
        }
    }

    // MARK: - Helper Views

    /// Displays a page of Bible text without scrolling
    private func pageView(_ page: OptimizedPageSlice, size: CGSize) -> some View {
        Text(page.content)
            .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
            .padding(.vertical, LayoutMetrics.verticalPagePadding)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .clipped()
            .onTapGesture { location in
                // Find which verse was tapped based on location
                if let tappedVerse = findVerseAtLocation(location, in: page, size: size) {
                    selectedVerse = tappedVerse
                    showSummaryPopup = true
                }
            }
            .onChange(of: pageGenerator.currentPage?.startVerse) { _, _ in
                if let newPage = pageGenerator.currentPage {
                    updateCurrentPageInfo(newPage)
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
    
    /// Finds which verse was tapped based on the tap location
    private func findVerseAtLocation(_ location: CGPoint, in page: OptimizedPageSlice, size: CGSize) -> VerseKey? {
        // Simple approach: divide the page into equal sections for each verse
        let pageHeight = size.height - (LayoutMetrics.verticalPagePadding * 2)
        let verseCount = page.verseKeys.count
        
        if verseCount == 0 { return nil }
        
        let adjustedY = location.y - LayoutMetrics.verticalPagePadding
        let verseHeight = pageHeight / CGFloat(verseCount)
        let verseIndex = Int(adjustedY / verseHeight)
        
        if verseIndex >= 0 && verseIndex < page.verseKeys.count {
            return page.verseKeys[verseIndex]
        }
        
        return nil
    }

    /// Handles swipe gestures for navigation
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

    /// Updates the current page info display
    private func updateCurrentPageInfo(_ page: OptimizedPageSlice) {
        currentPageInfo = page.navTitle
    }

    /// Displays an error message
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Error Loading Page")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task {
                    await pageGenerator.generatePage(startingAt: initialVerse)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
