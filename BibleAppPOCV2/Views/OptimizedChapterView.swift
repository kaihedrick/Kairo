// filepath: BibleAppPOCV2/Views/OptimizedChapterView.swift
import SwiftUI

struct OptimizedChapterView: View {
    let bookName: String
    let chapterCount: Int
    @Binding var navigationPath: [BibleNavigationRoute]

    @State private var isNavigating = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    private let tileSize: CGFloat = 50

    // Helper function to get verse count for a specific chapter
    private func getVerseCount(forChapter chapter: Int) -> Int {
        // For now, use reasonable defaults based on common Bible verse counts
        // In a production app, this would be pre-calculated or cached
        return getEstimatedVerseCount(forBook: bookName, chapter: chapter)
    }

    private func getEstimatedVerseCount(forBook book: String, chapter: Int) -> Int {
        // Simplified verse count estimation based on book and chapter
        // In a production app, this would be stored in the database
        switch book {
        case "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy":
            return chapter <= 10 ? 30 : chapter <= 20 ? 25 : 20
        case "Psalms":
            return chapter <= 50 ? 20 : chapter <= 100 ? 15 : 10
        case "Matthew", "Mark", "Luke", "John":
            return 25
        case "Acts":
            return 30
        case "Romans", "I Corinthians", "II Corinthians", "Galatians", "Ephesians":
            return 20
        default:
            return 25 // Default fallback
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .background(LG.backgroundMaterial)
                .ignoresSafeArea()

            ScrollView {
                GlassCard {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(1...chapterCount, id: \.self) { chapterNumber in
                            Button(action: {
                                let verseCount = getVerseCount(forChapter: chapterNumber)
                                
                                // Set navigation state to prevent competing animations during push
                                isNavigating = true
                                navigationPath.append(.verses(book: bookName, chapter: chapterNumber, verseCount: verseCount))
                                
                                // Reset navigation state after push animation completes
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    isNavigating = false
                                }
                            }) {
                                ChapterTileView(chapterNumber: chapterNumber)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(LG.padding)
                }
                .padding(LG.padding)
            }
        }
        .background(HighHzHint()) // 120Hz optimization for chapter selection
        .navigationTitle("\(bookName) - Chapters")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Prefetch verse counts for first few chapters
            prewarmChapterData()
        }
    }
    
    // MARK: - 120Hz Optimizations
    
    /// Prefetch verse counts for first few chapters to improve responsiveness
    private func prewarmChapterData() {
        Task.detached(priority: .utility) {
            // Prefetch verse counts for first 5 chapters
            let chaptersToPrefetch = Array(1...min(5, chapterCount))
            for chapter in chaptersToPrefetch {
                // Note: This is a placeholder - implement actual prefetching logic
                print("Prefetching data for chapter: \(chapter)")
            }
        }
    }
}