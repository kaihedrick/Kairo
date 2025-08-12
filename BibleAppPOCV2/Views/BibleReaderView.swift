// filepath: BibleAppPOCV2/Views/BibleReaderView.swift

import SwiftUI
import CoreGraphics
struct BibleReaderView: View {
    @StateObject private var pageGenerator: OnDemandPageGenerator
    @State private var currentPageInfo: String = ""
    @State private var showingPerformanceOverlay = false
    @State private var cacheStats: (hitRate: Double, size: Int) = (0.0, 0)

    // For gesture handling
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    
    // For summary popup
    @State private var showingSummaryPopup = false
    @State private var selectedVerse: VerseSummary?

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
                
                // Summary Popup Overlay
                if showingSummaryPopup, let summary = selectedVerse {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingSummaryPopup = false
                        }
                    
                    VerseSummaryPopupView(summary: summary) {
                        showingSummaryPopup = false
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 50)
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
                handleTextTap(location: location, page: page, size: size)
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

    /// Handles tap on text to show summary for the tapped verse
    private func handleTextTap(location: CGPoint, page: OptimizedPageSlice, size: CGSize) {
        // Find the verse that was tapped based on location
        guard let tappedVerse = findVerseAtLocation(location: location, page: page, size: size) else {
            print("⚠️ No verse found at tap location")
            return
        }
        
        // Get the verse text from the Bible data - extract ONLY the specific verse
        Task {
            let verseText = await extractVerseText(for: tappedVerse, from: String(page.content.characters))
            
            // Create a complete verse string that includes both reference and text
            // This format matches what the VerseSummaryViewModel.parseVerse function expects
            let completeVerseString = "\(tappedVerse.description) \(verseText)"
            
            // Create verse summary
            let summary = VerseSummary(
                reference: tappedVerse.description,
                book: tappedVerse.book,
                chapter: tappedVerse.chapter,
                verse: tappedVerse.verse,
                summaryText: completeVerseString, // Pass the complete verse string, not just the text
                modelVersion: "GPT-2 Bible Commentary Model"
            )
            
            await MainActor.run {
                selectedVerse = summary
                showingSummaryPopup = true
            }
            
            print("🎯 Tapped verse: \(tappedVerse.description)")
            print("📝 Complete verse string: '\(completeVerseString.prefix(100))...'")
            print("📝 Extracted text length: \(verseText.count) characters")
        }
    }
    
    /// Finds the verse at the given tap location
    private func findVerseAtLocation(location: CGPoint, page: OptimizedPageSlice, size: CGSize) -> VerseKey? {
        // Calculate which verse was tapped based on vertical position
        let tapY = location.y
        let pageHeight = size.height
        let verseCount = page.verseKeys.count
        
        if verseCount == 0 { return nil }
        
        // Calculate verse height and find which verse was tapped
        let verseHeight = pageHeight / CGFloat(verseCount)
        let verseIndex = Int(tapY / verseHeight)
        
        // Ensure index is within bounds
        let clampedIndex = max(0, min(verseIndex, verseCount - 1))
        let tappedVerse = page.verseKeys[clampedIndex]
        
        print("📍 Tap at Y: \(tapY), page height: \(pageHeight), verse count: \(verseCount)")
        print("🎯 Calculated verse index: \(clampedIndex), selected: \(tappedVerse.description)")
        
        return tappedVerse
    }
    
    /// Extracts the text for a specific verse from the page content
    private func extractVerseText(for verse: VerseKey, from content: String) async -> String {
        // Instead of trying to parse the combined content, we should get the verse text
        // directly from the Bible data loader for the specific verse
        // This ensures we get exactly the verse we want, not parsed content from the page
        
        // Load the specific verse text from the Bible data
        if let verseText = await loadSpecificVerseText(for: verse) {
            print("✅ Loaded specific verse text for \(verse.description): '\(verseText.prefix(50))...'")
            return verseText
        }
        
        // Fallback: try to extract by looking for verse numbers in the content
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("\(verse.verse) ") {
                let verseText = String(trimmedLine.dropFirst("\(verse.verse) ".count))
                print("✅ Found verse \(verse.verse) in line: '\(verseText.prefix(50))...'")
                return verseText
            }
        }
        
        // Last resort: return a small portion of content around where the verse should be
        print("⚠️ Could not extract specific verse text, returning limited content")
        let words = content.components(separatedBy: .whitespaces)
        let maxWords = min(20, words.count)
        return words.prefix(maxWords).joined(separator: " ")
    }
    
    /// Loads the specific verse text from the Bible data loader
    private func loadSpecificVerseText(for verse: VerseKey) async -> String? {
        // Use the legacy loader that has a loadVerse method for single verses
        let loader = LegacyOptimizedBibleDataLoader()
        
        // Load ONLY the specific verse, not the whole chapter
        guard let verseData = await loader.loadVerse(book: verse.book, chapter: verse.chapter, verse: verse.verse) else {
            print("❌ Could not load specific verse \(verse.description)")
            return nil
        }
        
        print("✅ Successfully loaded specific verse \(verse.description) from Bible data")
        return verseData.text
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
