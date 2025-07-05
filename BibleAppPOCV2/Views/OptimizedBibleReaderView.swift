import SwiftUI

struct OptimizedBibleReaderView: View {
    @StateObject private var generator = OnDemandPageGenerator(pageSize: .zero)
    let initialVerse: (book: String, chapter: Int, verse: Int)
    @State private var banner = ""

    var body: some View {
        GeometryReader { geo in
            let padH: CGFloat = 24
            let padV: CGFloat = 36
            let size = CGSize(
                width: geo.size.width - padH * 2,
                height: geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - padV
            )

            ZStack {
                if let page = generator.currentPage {
                    pageView(page, size: size)
                } else {
                    ProgressView()
                }
            }
            .onAppear {
                generator.updatePageSize(size)
                Task { await generator.generatePage(startingAt: initialVerse) }
            }
            .onChange(of: size) { newSize in
                generator.updatePageSize(newSize)
            }
        }
        .navigationTitle(banner)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: generator.currentPage?.startVerse) { _ in
            if let page = generator.currentPage {
                let s = page.startVerse
                let e = page.endVerse
                banner = "\(s.book.prefix(3)) \(s.chapter):\(s.verse)–\(e.chapter):\(e.verse)"
            }
        }
    }

    private func pageView(_ page: OptimizedPageSlice, size: CGSize) -> some View {
        Text(page.content)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .clipped()
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
