// filepath: BibleAppPOCV2/Views/BibleReaderView.swift

import SwiftUI
import CoreGraphics
import UIKit

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

    // MARK: - Verse Tap Overlay (TextKit Precision)

    private struct VerseTapOverlay: UIViewRepresentable {
        let nsText: NSAttributedString
        let verseMap: [(NSRange, VerseKey)]
        let contentInsets: UIEdgeInsets
        let onTap: (VerseKey) -> Void

        func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

        func makeUIView(context: Context) -> OverlayView {
            let view = OverlayView()
            view.isOpaque = false
            view.backgroundColor = .clear
            view.textContainerInset = contentInsets
            view.update(text: nsText, map: verseMap)

            // Tap recognizer that yields to scrolling/swiping
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tap.cancelsTouchesInView = false // do not block scroll or SwiftUI gestures
            tap.delegate = context.coordinator
            view.addGestureRecognizer(tap)

            // Make taps require ScrollView pan to fail (so swipes win)
            DispatchQueue.main.async {
                if let scrollView = context.coordinator.findScrollView(from: view) {
                    tap.require(toFail: scrollView.panGestureRecognizer)
                }
            }

            context.coordinator.view = view
            return view
        }

        func updateUIView(_ uiView: OverlayView, context: Context) {
            uiView.textContainerInset = contentInsets
            uiView.update(text: nsText, map: verseMap)
        }

        // MARK: TextKit‑backed view
        final class OverlayView: UIView {
            private let textStorage = NSTextStorage()
            private let layoutManager = NSLayoutManager()
            private let textContainer = NSTextContainer(size: .zero)

            private var verseMap: [(NSRange, VerseKey)] = []
            var textContainerInset: UIEdgeInsets = .zero { didSet { setNeedsLayout() } }

            override init(frame: CGRect) {
                super.init(frame: frame)
                isUserInteractionEnabled = true
                layoutManager.usesFontLeading = true
                layoutManager.allowsNonContiguousLayout = false
                textContainer.lineFragmentPadding = 0
                textContainer.maximumNumberOfLines = 0
                textContainer.lineBreakMode = .byWordWrapping
                layoutManager.addTextContainer(textContainer)
                textStorage.addLayoutManager(layoutManager)
            }
            required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

            override func layoutSubviews() {
                super.layoutSubviews()
                let w = bounds.width - (textContainerInset.left + textContainerInset.right)
                let h = bounds.height - (textContainerInset.top + textContainerInset.bottom)
                textContainer.size = CGSize(width: max(0, w), height: max(0, h))
            }

            func update(text: NSAttributedString, map: [(NSRange, VerseKey)]) {
                textStorage.setAttributedString(text)
                verseMap = map
                setNeedsLayout()
            }

            func verse(at point: CGPoint) -> VerseKey? {
                let pt = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
                guard pt.x >= 0, pt.y >= 0 else { return nil }
                let glyphIndex = layoutManager.glyphIndex(for: pt, in: textContainer)
                let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
                for (range, key) in verseMap where NSLocationInRange(charIndex, range) { return key }
                return nil
            }
        }

        // MARK: Coordinator
        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            var onTap: (VerseKey) -> Void
            weak var view: OverlayView?
            init(onTap: @escaping (VerseKey) -> Void) { self.onTap = onTap }

            @objc func handleTap(_ tap: UITapGestureRecognizer) {
                guard let view = view else { return }
                let loc = tap.location(in: view)
                if let key = view.verse(at: loc) { onTap(key) }
            }

            // Find enclosing UIScrollView (SwiftUI ScrollView host)
            func findScrollView(from v: UIView?) -> UIScrollView? {
                var cur = v?.superview
                while let c = cur { if let sv = c as? UIScrollView { return sv }; cur = c.superview }
                return nil
            }

            // Don't block other gestures (DragGesture, scrolling)
            func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        }
    }

    // MARK: - Helper Functions

    /// Build one NSAttributedString body and an exact NSRange→VerseKey map.
    private func buildBodyNS(from runs: [PageSegment]) -> (NSAttributedString, [(NSRange, VerseKey)]) {
        let out = NSMutableAttributedString()
        var map: [(NSRange, VerseKey)] = []

        for seg in runs {
            let nsSeg = NSAttributedString(seg.attributed)
            let start = out.length
            out.append(nsSeg)
            // Ensure paragraph flow: append a space (not a newline) if needed
            if !String(seg.attributed.characters).hasSuffix(" ") {
                out.append(NSAttributedString(string: " "))
            }
            let end = out.length
            map.append((NSRange(location: start, length: end - start), seg.verseKey))
        }
        return (out, map)
    }

    // MARK: - Helper Views

    /// Displays a page of Bible text with continuous Kindle-style flow and precise verse tapping
    private func pageView(_ page: DatabasePageContent, size: CGSize) -> some View {
        // Build a single NSAttributedString + exact verse ranges from the same instance
        let (nsBody, verseMap) = buildBodyNS(from: page.verseRuns)
        let fullText = AttributedString(nsBody)

        return ScrollView { // intrinsic height; no forced page height
            ZStack(alignment: .topLeading) {
                Text(fullText)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
                    .padding(.vertical, LayoutMetrics.verticalPagePadding)

                VerseTapOverlay(nsText: nsBody,
                                verseMap: verseMap,
                                contentInsets: UIEdgeInsets(top: LayoutMetrics.verticalPagePadding,
                                                            left: LayoutMetrics.horizontalPagePadding,
                                                            bottom: LayoutMetrics.verticalPagePadding,
                                                            right: LayoutMetrics.horizontalPagePadding)) { verseKey in
                    Task { await handleVerseTap(verseKey) }
                }
                .allowsHitTesting(true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
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

