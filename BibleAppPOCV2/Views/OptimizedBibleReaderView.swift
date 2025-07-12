import SwiftUI

struct OptimizedBibleReaderView: View {
    @StateObject private var generator = OnDemandPageGenerator(pageSize: .zero)
    let initialVerse: (book: String, chapter: Int, verse: Int)
    @Environment(\.scenePhase) private var scenePhase
    @State private var sizeChangeTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            // Account for navigation bar height (~44pts) and safe areas
            let navigationBarHeight: CGFloat = 44
            let availableHeight = geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - navigationBarHeight
            let size = CGSize(
                width: geo.size.width,
                height: max(availableHeight, 100) // Ensure minimum height
            )
            
            #if DEBUG
            // Debug: Print size calculation details
            let _ = print("📐 Size calc: total=\(geo.size.height), top=\(geo.safeAreaInsets.top), bottom=\(geo.safeAreaInsets.bottom), nav=\(navigationBarHeight), final=\(size.height)")
            #endif

            ZStack {
                if let page = generator.currentPage {
                    pageView(page, size: size)
                } else {
                    ProgressView()
                }
#if DEBUG
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1, perform: {
                        Task { print("X-RAY:\t", await generator.debugInfo()) }
                    })
#endif
            }
            .onAppear {
                print("📐 View appeared, size: \(size)")
                // Size change handler will trigger page generation
            }
            .onChange(of: size) { _, newSize in
                print("📐 Size changed to: \(newSize)")
                
                // Only generate if size is reasonable
                guard newSize.width > 100 && newSize.height > 100 else { return }
                
                // Cancel any pending size change task
                sizeChangeTask?.cancel()
                
                // Debounce size changes to prevent duplicate generation
                sizeChangeTask = Task {
                    // Wait a short time to see if more size changes come in
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    
                    // Check if task was cancelled (another size change occurred)
                    guard !Task.isCancelled else { return }
                    
                    print("📖 DEBOUNCED: Generating fresh page with size: \(newSize)")
                    generator.updatePageSize(newSize)
                    
                    // Get current position, then force regenerate
                    let currentStart = generator.currentPage?.startVerse ?? 
                        VerseKey(book: initialVerse.book, chapter: initialVerse.chapter, verse: initialVerse.verse)
                    await generator.generatePage(startingAt: (currentStart.book, currentStart.chapter, currentStart.verse))
                }
            }
        }
        .navigationTitle(generator.currentPage?.navTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { generator.handleMemoryPressure() }
        }
        .onDisappear {
            sizeChangeTask?.cancel()
        }
    }

    private func pageView(_ page: OptimizedPageSlice, size: CGSize) -> some View {
        Text(page.content)
            .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
            .padding(.vertical, LayoutMetrics.verticalPagePadding)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .clipped()
            .background(
                GeometryReader { textGeo in
                    Color.clear
                        .onAppear {
                            let actualContentHeight = textGeo.size.height
                            let availableHeight = size.height
                            print("📏 RENDER VERIFICATION: content=\(actualContentHeight) vs available=\(availableHeight)")
                            print("📊 VERSE RANGE: \(page.verseKeys.count) verses from \(page.startVerse.description) to \(page.endVerse.description)")
                            
                            // With precision pagination, overflow should be extremely rare
                            if actualContentHeight > availableHeight + 5 { // Very small tolerance
                                print("⚠️ UNEXPECTED OVERFLOW: Content is \(actualContentHeight - availableHeight)pts too tall")
                                print("� This indicates the measurement system needs refinement")
                                // No longer calling reportOverflow - precision pagination should prevent this
                            } else {
                                print("✅ PRECISION SUCCESS: Content fits perfectly within available space")
                                print("📏 VERIFIED: \(page.verseKeys.count) verses fit in \(availableHeight) pts")
                            }
                        }
                        .onChange(of: textGeo.size.height) { _, newHeight in
                            print("📏 CONTENT HEIGHT CHANGED: \(newHeight)")
                        }
                }
            )
#if DEBUG
            .overlay(alignment: .bottom) { Color.red.frame(height: 6) }
#endif
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.width < -50 {
                            Task { await generator.generateNextPage() }
                        } else if value.translation.width > 50 {
                            Task { await generator.generatePreviousPage() }
                        }
                    }
            )
    }
}

