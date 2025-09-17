// filepath: BibleAppPOCV2/Views/OptimizedVerseView.swift
import SwiftUI

struct OptimizedVerseView: View {
    let bookName: String
    let chapterNumber: Int

    @State private var chapterContent: DatabaseChapter?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var pageIndex: Int = 0

    private let loader = DatabaseBibleDataLoader.shared
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
                Group {
                    if isLoading {
                        GlassCard {
                            VStack(spacing: LG.padding) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Loading \(bookName) \(chapterNumber)...")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(LG.padding)
                    } else if let error = loadError {
                        GlassCard {
                            VStack(spacing: LG.padding) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundStyle(.orange)

                                Text("Failed to load chapter")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(error.localizedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)

                                Button("Retry") {
                                    Task {
                                        await loadChapterContent()
                                    }
                                }
                                .glassButtonStyle()
                                .padding(.top)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(LG.padding)
                    } else if let content = chapterContent {
                        TabView(selection: $pageIndex) {
                            ScrollView {
                                GlassCard {
                                    LazyVGrid(columns: columns, spacing: LG.smallPadding) {
                                        ForEach(content.verses, id: \.verseNumber) { verse in
                                            NavigationLink {
                                                destinationView(verse: verse)
                                            } label: {
                                                VerseTileView(verseNumber: verse.verseNumber)
                                                    .frame(width: tileSize, height: tileSize)
                                                    .glassTile(cornerRadius: 12, id: "verse-\(verse.verseNumber)", namespace: glassNamespace)
                                            }
                                            .buttonStyle(PlainButtonStyle()) // Ensure proper tap behavior
                                        }
                                    }
                                    .padding(LG.padding)
                                }
                                .padding(LG.padding)
                            }
                            .tag(0)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
            }
            .navigationTitle("\(bookName) \(chapterNumber) - Verses")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadChapterContent()
            }
        }
    }

    @ViewBuilder
    private func destinationView(verse: DatabaseVerse) -> some View {
        GeometryReader { geometry in
            if geometry.size.height > 50 {
                BibleReaderView(
                    pageSize: CGSize(
                        width: geometry.size.width,
                        height: geometry.size.height
                    ),
                    initialVerse: (bookName, chapterNumber, verse.verseNumber)
                )
            } else {
                Color.clear
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadChapterContent() async {
        isLoading = true
        loadError = nil

        do {
            let result = try await loader.loadChapter(book: bookName, chapter: chapterNumber)
            switch result {
            case .success(let chapter):
                chapterContent = chapter
            case .failure(let error):
                throw error
            }

            isLoading = false
        } catch {
            loadError = error
            isLoading = false
        }
    }
}