// filepath: BibleAppPOCV2/Views/OptimizedChapterView.swift
import SwiftUI

struct OptimizedChapterView: View {
    let bookName: String
    let chapterCount: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    private let tileSize: CGFloat = 50

    // Glass effect namespace for native iOS 26+ blur
    @Namespace private var glassNamespace

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Liquid Glass Background
                Color.clear
                    .background(LG.backgroundMaterial)
                    .ignoresSafeArea()

                // Main content layer
                ScrollView {
                    GlassCard {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(1...chapterCount, id: \.self) { chapterNumber in
                                NavigationLink {
                                    OptimizedVerseView(bookName: bookName, chapterNumber: chapterNumber)
                                } label: {
                                    ChapterTileView(chapterNumber: chapterNumber)
                                        .frame(width: tileSize, height: tileSize)
                                        .glassTile(cornerRadius: 12, id: "chapter-\(chapterNumber)", namespace: glassNamespace)
                                }
                                .buttonStyle(PlainButtonStyle()) // Ensure proper tap behavior
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
}