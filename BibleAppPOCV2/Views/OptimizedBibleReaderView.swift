import SwiftUI

struct OptimizedBibleReaderView: View {
    @StateObject private var generator = OnDemandPageGenerator(pageSize: .zero)
    let initialVerse: (book: String, chapter: Int, verse: Int)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(
                width: geo.size.width,
                height: geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom
            )

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
            .onChange(of: size) { newSize in
                generator.updatePageSize(newSize)
                // Regenerate current page with new size
                if let currentStart = generator.currentPage?.startVerse {
                    Task { 
                        await generator.generatePage(startingAt: (currentStart.book, currentStart.chapter, currentStart.verse)) 
                    }
                }
            }
        }
        .navigationTitle(generator.currentPage?.navTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { phase in
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

