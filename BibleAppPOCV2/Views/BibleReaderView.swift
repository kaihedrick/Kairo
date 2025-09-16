// filepath: BibleAppPOCV2/Views/BibleReaderView.swift

import SwiftUI
import CoreGraphics

// Import EnhancedBibleDatabase for direct verse lookups
import Foundation
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
    private func pageView(_ page: DatabasePageContent, size: CGSize) -> some View {
        Text(page.content)
            .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
            .padding(.vertical, LayoutMetrics.verticalPagePadding)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .clipped()
            .onTapGesture { location in
                Task {
                    await handleTextTap(location: location, page: page, size: size)
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

    /// Handles tap on text to show summary for the tapped verse
    private func handleTextTap(location: CGPoint, page: DatabasePageContent, size: CGSize) async {
        // Find the verse that was tapped based on location
        guard let tappedVerse = findVerseAtLocation(location: location, page: page, size: size) else {
            print("⚠️ No verse found at tap location")
            return
        }
        
        // Create verse summary with just the reference (no text extraction needed)
        #if DEBUG
        print("🎯 TAPPED VERSE: \(tappedVerse.description)")
        #endif

        let summary = VerseSummary(
            reference: tappedVerse.description,
            book: tappedVerse.book,
            chapter: tappedVerse.chapter,
            verse: tappedVerse.verse,
            summaryText: tappedVerse.description, // Just the reference string
            modelVersion: "Enhanced Bible Database (Database Only)"
        )

        await MainActor.run {
            selectedVerse = summary
            showingSummaryPopup = true
        }
    }
    
    /// Finds the verse at the given tap location using EnhancedBibleDatabase
    private func findVerseAtLocation(location: CGPoint, page: DatabasePageContent, size: CGSize) -> VerseKey? {
        let tapY = location.y
        let pageHeight = size.height
        let verseCount = page.verseKeys.count

        if verseCount == 0 { return nil }

        #if DEBUG
        print("📍 Tap at Y: \(tapY), page height: \(pageHeight), verse count: \(verseCount)")
        print("📄 Current page: \(page.startVerse.description) to \(page.endVerse.description)")
        #endif

        // Use simple calculation - divide page height by verse count
        let verseHeight = pageHeight / CGFloat(verseCount)
        let verseIndex = Int(tapY / verseHeight)
        let clampedIndex = max(0, min(verseIndex, verseCount - 1))
        let tappedVerse = page.verseKeys[clampedIndex]

        #if DEBUG
        print("🎯 CALCULATED VERSE: index \(clampedIndex), selected \(tappedVerse.description)")
        print("📊 Verse height: \(String(format: "%.1f", verseHeight)), tap ratio: \(String(format: "%.3f", tapY/pageHeight))")
        #endif

        return tappedVerse
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
    private func updateCurrentPageInfo(_ page: DatabasePageContent) {
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

