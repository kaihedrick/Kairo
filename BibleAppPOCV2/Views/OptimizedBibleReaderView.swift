import SwiftUI

struct OptimizedBibleReaderView: View {
    @StateObject private var generator = OnDemandPageGenerator(pageSize: .zero)
    let initialVerse: (book: String, chapter: Int, verse: Int)
    @Environment(\.scenePhase) private var scenePhase

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
                generator.updatePageSize(size)
                Task { await generator.generatePage(startingAt: initialVerse) }
            }
            .onChange(of: size) { _, newSize in
                generator.updatePageSize(newSize)
                // Note: updatePageSize already clears cache and will regenerate on next access
                // No need to explicitly regenerate here as it causes duplicate generation
            }
        }
        .navigationTitle(generator.currentPage?.navTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { generator.handleMemoryPressure() }
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
                            print("📏 ACTUAL RENDER: content=\(actualContentHeight) vs available=\(availableHeight)")
                            
                            // If content overflows significantly, we need to regenerate
                            if actualContentHeight > availableHeight + 10 { // 10pt tolerance
                                print("⚠️ OVERFLOW: Content is \(actualContentHeight - availableHeight)pts too tall")
                                print("🔄 Page has \(page.verseKeys.count) verses, should have fewer")
                                
                                // Provide feedback to generator about actual fit
                                Task {
                                    await generator.reportOverflow(
                                        actualHeight: actualContentHeight,
                                        availableHeight: availableHeight,
                                        segmentCount: page.verseKeys.count
                                    )
                                }
                            } else {
                                print("✅ FITS: Content fits within available space")
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

