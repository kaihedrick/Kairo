
import SwiftUI

struct BibleReaderView: View {
    @StateObject private var pageGenerator: OnDemandPageGenerator
    @State private var currentPageInfo: String = ""
    @State private var showingPerformanceOverlay = false
    @State private var cacheStats: (hitRate: Double, size: Int) = (0.0, 0)

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
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Current location indicator with verse range
                if !currentPageInfo.isEmpty {
                    Text(currentPageInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                }

                // Main content area
                ZStack {
                    if pageGenerator.isGenerating {
                        ProgressView("Loading page...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let currentPage = pageGenerator.currentPage {
                        pageView(currentPage.toOptimizedPageSlice())
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
            .task { // Use .task instead of .onAppear for async work
                if pageGenerator.currentPage == nil {
                    await pageGenerator.generatePage(startingAt: initialVerse)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                pageGenerator.handleMemoryPressure()
            }
        }
    }

    // MARK: - Helper Views

    /// Displays a page of Bible text
    private func pageView(_ page: OptimizedPageSlice) -> some View {
        ScrollView {
            Text(page.content)
                .padding(.horizontal, 16)  // Proper margins
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)  // Left alignment to prevent cutoff
                .multilineTextAlignment(.leading)
        }
        .onChange(of: pageGenerator.currentPage?.startKey) { _, _ in
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
