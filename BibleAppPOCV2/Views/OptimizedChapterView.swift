// filepath: BibleAppPOCV2/Views/OptimizedChapterView.swift
import SwiftUI

struct OptimizedChapterView: View {
    let bookName: String
    let chapterCount: Int
    @Binding var navigationPath: [BibleNavigationRoute]

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
                                navigationPath.append(.verses(book: bookName, chapter: chapterNumber, verseCount: verseCount))
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
        .navigationTitle("\(bookName) - Chapters")
        .navigationBarTitleDisplayMode(.large)
    }
}