// filepath: BibleAppPOCV2/Views/BibleReaderView.swift

import SwiftUI
import CoreGraphics

// Import EnhancedBibleDatabase for direct verse lookups
import Foundation

// MARK: - Notifications
extension Notification.Name {
    static let kairoVerseTapped = Notification.Name("kairoVerseTapped")
}

// MARK: - Verse Frame Hit Testing & Payload
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

struct VerseFrame: Equatable, Hashable {
    let key: VerseKey
    let frame: CGRect

    var description: String {
        "\(key.description) @ (\(Int(frame.midX)), \(Int(frame.midY)))"
    }
}

struct VerseFramesKey: PreferenceKey {
    static var defaultValue: [VerseFrame] = []
    static func reduce(value: inout [VerseFrame], nextValue: () -> [VerseFrame]) {
        value += nextValue()
    }
}

struct VerseHitTester {
    /// Frame-accurate hit testing using captured verse frames
    static func verseKey(for point: CGPoint, in frames: [VerseFrame]) -> VerseKey? {
        // First try exact containment
        if let exactMatch = frames.first(where: { $0.frame.contains(point) }) {
            #if DEBUG
            print("🎯 FRAME HIT: Exact match \(exactMatch.description)")
            #endif
            return exactMatch.key
        }

        // Fallback to nearest verse by vertical distance
        let nearest = frames.min(by: { abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y) })
        if let nearest = nearest {
            #if DEBUG
            print("🎯 FRAME HIT: Nearest match \(nearest.description) (tap @ \(Int(point.x)), \(Int(point.y)))")
            #endif
            return nearest.key
        }

        return nil
    }

    /// Legacy prefix-sum method (fallback)
    static func index(for tapY: CGFloat,
                     contentTop: CGFloat,
                     heights: [CGFloat]) -> Int {
        // Convert to content-local Y coordinate
        var y = max(0, tapY - contentTop)
        var accumulated: CGFloat = 0

        for (i, h) in heights.enumerated() {
            let next = accumulated + h
            if y < next { return i }
            accumulated = next
        }

        return max(0, heights.count - 1) // clamp to last valid index
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

    // For frame-based hit testing
    @State private var verseFrames: [VerseFrame] = []

    // Debug overlay for frame visualization
    #if DEBUG
    @State private var showFrameOverlay = false
    #endif

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

    /// Displays a page of Bible text without scrolling
    private func pageView(_ page: DatabasePageContent, size: CGSize) -> some View {
        Text(page.content)
            .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
            .padding(.vertical, LayoutMetrics.verticalPagePadding)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .clipped()
            .coordinateSpace(name: "BibleScroll")
            .onPreferenceChange(VerseFramesKey.self) { frames in
                self.verseFrames = frames
                #if DEBUG
                print("📐 CAPTURED \(frames.count) verse frames for hit testing")
                #endif
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
            // Debug overlay for frame visualization
            #if DEBUG
            .overlay(
                Group {
                    if showFrameOverlay {
                        ZStack {
                            ForEach(verseFrames, id: \.key) { frame in
                                Rectangle()
                                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                    .frame(width: frame.frame.width, height: frame.frame.height)
                                    .position(x: frame.frame.midX, y: frame.frame.midY)
                                    .overlay(
                                        Text(frame.key.description)
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                            .background(Color.white.opacity(0.8))
                                            .padding(2)
                                            .position(x: frame.frame.midX, y: frame.frame.minY - 10)
                                    )
                            }
                        }
                    }
                }
            )
            .onTapGesture(count: 2) {
                showFrameOverlay.toggle()
                #if DEBUG
                print("🔍 DEBUG OVERLAY: \(showFrameOverlay ? "ENABLED" : "DISABLED")")
                #endif
            }
            #endif
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
    
    /// Finds the verse at the given tap location using EnhancedBibleDatabase
    private func findVerseAtLocation(location: CGPoint, page: DatabasePageContent, size: CGSize) -> VerseKey? {
        let tapY = location.y
        let pageHeight = size.height
        let verseCount = page.verseKeys.count

        if verseCount == 0 { return nil }

        // IMPROVED: Use page start verse as base to eliminate off-by-one errors
        let pageStartVerse = page.startVerse.verse

        // For now, use improved uniform height calculation that prevents overflow
        // TODO: Replace with VerseHitTester when per-verse heights are available
        let contentAreaHeight = pageHeight * 0.9 // Account for padding/margins
        let verseHeight = contentAreaHeight / CGFloat(verseCount)

        // Use floor division to prevent overflow to next verse
        let rawIndex = floor(tapY / verseHeight)
        let clampedIndex = max(0, min(Int(rawIndex), verseCount - 1))

        // DIRECT: Use the verse key from the page's verseKeys array (already correctly mapped)
        let tappedVerse = page.verseKeys[clampedIndex]

        #if DEBUG
        print("📍 Tap at Y: \(tapY), page height: \(pageHeight), verse count: \(verseCount)")
        print("📄 Current page: \(page.startVerse.description) to \(page.endVerse.description)")
        print("🧭 TAP idx=\(clampedIndex) pageStart=\(pageStartVerse) → verse=\(tappedVerse.verse)")
        print("🎯 CALCULATED VERSE: index \(clampedIndex), selected \(tappedVerse.description)")
        print("📊 Content height: \(String(format: "%.1f", contentAreaHeight)), verse height: \(String(format: "%.1f", verseHeight))")

        // Verify no extra +1 is being added
        let expectedVerseFromIndex = pageStartVerse + clampedIndex
        if tappedVerse.verse != expectedVerseFromIndex {
            print("⚠️ VERSE MISMATCH: Expected verse \(expectedVerseFromIndex) from index \(clampedIndex), but got \(tappedVerse.verse)")
        }

        // Add defensive assertion - validate the mapping
        assert(tappedVerse.chapter == page.startVerse.chapter, "Chapter mismatch - possible parsing error")
        assert(tappedVerse.verse >= page.startVerse.verse && tappedVerse.verse <= page.endVerse.verse,
               "Tap mapped outside page range: verse \(tappedVerse.verse) not in \(page.startVerse.verse)-\(page.endVerse.verse)")
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

