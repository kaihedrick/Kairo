// filepath: BibleAppPOCV2/Views/BibleReaderView.swift

import SwiftUI
import CoreGraphics

// Import EnhancedBibleDatabase for direct verse lookups
import Foundation

// MARK: - Notifications
extension Notification.Name {
    static let kairoVerseTapped = Notification.Name("kairoVerseTapped")
}

// MARK: - Verse Tap Payload
struct VerseTapPayload: Codable, Equatable {
    let book: String
    let chapter: Int
    let verse: Int

    var verseKey: VerseKey {
        VerseKey(book: book, chapter: chapter, verse: verse)
    }

    var description: String {
        "\(book) \(chapter):\(verse)"
    }
}
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
                // Liquid Glass Background
                Color.clear
                    .background(LG.backgroundMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !currentPageInfo.isEmpty {
                        GlassCard {
                            Text(currentPageInfo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, LG.padding)
                        .padding(.top, LG.smallPadding)
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

    /// Displays a page of Bible text with precise verse tapping
    private func pageView(_ page: DatabasePageContent, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // Render each verse as its own tappable button
            VStack(alignment: .leading, spacing: 6) {
                ForEach(page.verseRuns, id: \.id) { segment in
                    Button {
                        Task {
                            await handleVerseTap(segment.verseKey)
                        }
                    } label: {
                        Text(segment.attributed)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
            .padding(.vertical, LayoutMetrics.verticalPagePadding)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .coordinateSpace(name: "BibleScroll")
        }
        .gesture(
            DragGesture(minimumDistance: 20) // Standard swipe detection
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
        .onChange(of: pageGenerator.currentPage?.startVerse) { _, _ in
            if let newPage = pageGenerator.currentPage {
                updateCurrentPageInfo(newPage)
            }
        }
        .onAppear {
            updateCurrentPageInfo(page)
        }
    }
    /// Handles direct verse tap (when using verseRuns approach)
    @MainActor
    private func handleVerseTap(_ verseKey: VerseKey) async {
        #if DEBUG
        print("🎯 DIRECT VERSE TAP: \(verseKey.description)")
        #endif

        // Create payload and post notification (single source of truth)
        let payload = VerseTapPayload(book: verseKey.book, chapter: verseKey.chapter, verse: verseKey.verse)

        NotificationCenter.default.post(
            name: .kairoVerseTapped,
            object: nil,
            userInfo: ["payload": payload]
        )

        // Update UI state for popup display
        let summary = VerseSummary(
            reference: payload.description,
            book: payload.book,
            chapter: payload.chapter,
            verse: payload.verse,
            summaryText: payload.description,
            modelVersion: "Enhanced Bible Database (Database Only)"
        )

        selectedVerse = summary
        showingSummaryPopup = true
    }

    /// Handles tap on text to show summary for the tapped verse
    private func handleTextTap(location: CGPoint, page: DatabasePageContent, size: CGSize) async {
        // Find the verse that was tapped based on location
        guard let tappedVerse = findVerseAtLocation(location: location, page: page, size: size) else {
            print("⚠️ No verse found at tap location")
            return
        }

        #if DEBUG
        print("🎯 TAPPED VERSE: \(tappedVerse.description)")
        #endif

        // Create payload and post notification (single source of truth)
        let payload = VerseTapPayload(book: tappedVerse.book, chapter: tappedVerse.chapter, verse: tappedVerse.verse)

        NotificationCenter.default.post(
            name: .kairoVerseTapped,
            object: nil,
            userInfo: ["payload": payload]
        )

        // Update UI state for popup display
        let summary = VerseSummary(
            reference: payload.description,
            book: payload.book,
            chapter: payload.chapter,
            verse: payload.verse,
            summaryText: payload.description,
            modelVersion: "Enhanced Bible Database (Database Only)"
        )

        await MainActor.run {
            selectedVerse = summary
            showingSummaryPopup = true
        }
    }

    /// Finds the verse at the given tap location using improved verse detection
    private func findVerseAtLocation(location: CGPoint, page: DatabasePageContent, size: CGSize) -> VerseKey? {
        let tapY = location.y
        let pageHeight = size.height
        let verseCount = page.verseKeys.count

        if verseCount == 0 { return nil }

        // Calculate which verse was tapped based on vertical position
        // This uses a more accurate approach by considering text layout
        let textHeight = pageHeight - (LayoutMetrics.verticalPagePadding * 2)
        let verseHeight = textHeight / CGFloat(max(1, verseCount))

        // Find the verse index based on tap position
        let tappedIndex = Int((tapY - LayoutMetrics.verticalPagePadding) / verseHeight)

        // Clamp index to valid range
        let clampedIndex = max(0, min(verseCount - 1, tappedIndex))

        let tappedVerse = page.verseKeys[clampedIndex]

        #if DEBUG
        print("🎯 HIT TEST: tapY=\(Int(tapY)) textHeight=\(Int(textHeight)) verseHeight=\(Int(verseHeight))")
        print("🎯 SELECTED: \(tappedVerse.description) (index \(clampedIndex) of \(verseCount))")
        #endif

        return tappedVerse
    }
    
    /// Handles swipe gestures for navigation
    private func handleSwipeGesture(_ value: DragGesture.Value) {
        let horizontalAmount = value.translation.width
        let verticalAmount = value.translation.height

        // Only handle horizontal swipes for page navigation
        if abs(horizontalAmount) > abs(verticalAmount) && abs(horizontalAmount) > 50 {
            if horizontalAmount > 0 {
                // Swipe right - go to previous page
                Task {
                    await pageGenerator.generatePreviousPage()
                }
            } else {
                // Swipe left - go to next page
                Task {
                    await pageGenerator.generateNextPage()
                }
            }
        }
    }
    


    /// Updates the current page info display
    private func updateCurrentPageInfo(_ page: DatabasePageContent) {
        currentPageInfo = page.navTitle
    }

    /// Displays an error message
    private func errorView(_ error: String) -> some View {
        GlassCard {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                Text("Error Loading Page")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task {
                        await pageGenerator.generatePage(startingAt: initialVerse)
                    }
                }
                .glassButtonStyle()
            }
        }
        .padding(LG.padding)
    }
}

