// filepath: BibleAppPOCV2/Views/OptimizedVerseView.swift
import SwiftUI

struct OptimizedVerseView: View {
    let bookName: String
    let chapterNumber: Int
    let verseCount: Int
    @Binding var navigationPath: [BibleNavigationRoute]

    @State private var chapterContent: DatabaseChapter?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var pageIndex: Int = 0

    private let loader = DatabaseBibleDataLoader.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    private let tileSize: CGFloat = 50

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .background(LG.backgroundMaterial)
                .ignoresSafeArea()

            Group {
                if isLoading {
                    GlassCard {
                        VStack(spacing: LG.padding) {
                            ProgressView().scaleEffect(1.2)
                            Text("Loading \(bookName) \(chapterNumber)...")
                                .font(.headline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(LG.padding)
                } else if let error = loadError {
                    GlassCard {
                        VStack(spacing: LG.padding) {
                            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                            Text("Failed to load chapter").font(.headline)
                            Text(error.localizedDescription)
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Retry") { Task { await loadChapterContent() } }
                                .glassButtonStyle().padding(.top)
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
                                        Button(action: {
                                            navigationPath.append(.reader(book: bookName, chapter: chapterNumber, verse: verse.verseNumber))
                                        }) {
                                            VerseTileView(verseNumber: verse.verseNumber)
                                        }
                                        .buttonStyle(.plain)
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
        .background(HighHzHint()) // 120Hz optimization for verse selection
        .navigationTitle("\(bookName) \(chapterNumber) - Verses")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadChapterContent() }
    }

    @ViewBuilder
    private func destinationView(verse: DatabaseVerse) -> some View {
        GeometryReader { geometry in
            let safeSize = CGSize(
                width: geometry.size.width,
                height: max(geometry.size.height, 600) // Ensure minimum height during transitions
            )
            BibleReaderView(
                pageSize: safeSize,
                initialVerse: (bookName, chapterNumber, verse.verseNumber)
            )
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadChapterContent() async {
        isLoading = true
        loadError = nil

        do {
            // Small debounce to prevent rapid loading during navigation
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            let result = try await loader.loadChapter(book: bookName, chapter: chapterNumber)
            switch result {
            case .success(let chapter):
                await MainActor.run {
                    chapterContent = chapter
                    isLoading = false
                }
            case .failure(let error):
                await MainActor.run {
                    loadError = error
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                loadError = error
                isLoading = false
            }
        }
    }
}