import SwiftUI

struct OptimizedVerseView: View {
    let bookName: String
    let chapterNumber: Int
    
    @State private var chapterContent: ChapterContent?
    @State private var isLoading = true
    @State private var loadError: Error?
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    private let tileSize: CGFloat = 50
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading \(bookName) \(chapterNumber)...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    
                    Text("Failed to load chapter")
                        .font(.headline)
                    
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        Task {
                            await loadChapterContent()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let content = chapterContent {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(content.verses, id: \.id) { verse in
                            NavigationLink {
                                destinationView(verse: verse)
                            } label: {
                                Text("\(verse.verse)")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .frame(width: tileSize, height: tileSize)
                                    .glassBackground(cornerRadius: 10)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("\(bookName) \(chapterNumber)")
        .task {
            await loadChapterContent()
        }
    }
    
    @ViewBuilder
    private func destinationView(verse: VerseContent) -> some View {
        GeometryReader { geometry in
            OptimizedBibleReaderView(
                pageSize: CGSize(
                    width: geometry.size.width - 40,
                    height: geometry.size.height - 40
                ),
                initialVerse: (bookName, chapterNumber, verse.verse)
            )
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func loadChapterContent() async {
        isLoading = true
        loadError = nil
        
        do {
            chapterContent = await OptimizedBibleDataLoader.shared.loadChapterContent(
                book: bookName, 
                chapter: chapterNumber
            )
            
            if chapterContent == nil {
                throw NSError(
                    domain: "BibleReaderApp", 
                    code: 404, 
                    userInfo: [NSLocalizedDescriptionKey: "Chapter content not found"]
                )
            }
            
            isLoading = false
        } catch {
            loadError = error
            isLoading = false
        }
    }
}

// MARK: - Glass Background Modifier
extension View {
    func glassBackground(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}