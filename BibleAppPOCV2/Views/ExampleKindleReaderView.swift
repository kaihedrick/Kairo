// filepath: BibleAppPOCV2/Views/ExampleKindleReaderView.swift
// ExampleKindleReaderView.swift
// Example implementation showing how to use the new Kindle-like fixed page system

import SwiftUI
import Foundation

/// Example implementation showing how to use the new Kindle-like fixed page system
struct ExampleKindleReaderView: View {
    let book: String
    let chapter: Int
    @State private var pageEngine = PageEngine()
    @State private var body: NSAttributedString = .init(string: "")
    @State private var pages: [ReaderPage] = []
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if !pages.isEmpty {
                ReaderPager(
                    body: body,
                    pages: pages,
                    pageSize: UIScreen.main.bounds.size
                ) { verseKey in
                    handleVerseTap(verseKey)
                }
            } else {
                Text("No content available")
            }
        }
        .navigationTitle("\(book) \(chapter)")
        .task {
            await loadChapter()
        }
    }
    
    @MainActor
    private func loadChapter() async {
        // This is where you would load your chapter data
        // For now, we'll create some sample data
        
        // Sample verse runs (you would get this from your data loader)
        let sampleRuns: [PageSegment] = [
            PageSegment(
                attributed: AttributedString("1 In the beginning was the Word, and the Word was with God, and the Word was God. "),
                verseKey: VerseKey(book: book, chapter: chapter, verse: 1),
                isSplit: false
            ),
            PageSegment(
                attributed: AttributedString("2 He was with God in the beginning. "),
                verseKey: VerseKey(book: book, chapter: chapter, verse: 2),
                isSplit: false
            ),
            PageSegment(
                attributed: AttributedString("3 Through him all things were made; without him nothing was made that has been made. "),
                verseKey: VerseKey(book: book, chapter: chapter, verse: 3),
                isSplit: false
            )
        ]
        
        // Create typography and theme metrics
        let typography = TypographyMetrics(
            pointSize: 16,
            fontFamily: "System",
            fontWeight: "Regular"
        )
        
        let theme = ThemeMetrics(
            isDark: false,
            foregroundColor: "black",
            backgroundColor: "white"
        )
        
        // Paginate the content
        let (paginatedBody, paginatedPages) = pageEngine.paginate(
            book: book,
            chapter: chapter,
            runs: sampleRuns,
            pageSize: UIScreen.main.bounds.size,
            typography: typography,
            theme: theme
        )
        
        self.body = paginatedBody
        self.pages = paginatedPages
        self.isLoading = false
    }
    
    private func handleVerseTap(_ verseKey: VerseKey) {
        // Handle verse tap - this could navigate to a verse detail view
        print("Tapped verse: \(verseKey.description)")
        
        // Example: Post notification for verse tap
        NotificationCenter.default.post(
            name: .kairoVerseTapped,
            object: nil,
            userInfo: ["payload": VerseTapPayload(
                book: verseKey.book,
                chapter: verseKey.chapter,
                verse: verseKey.verse
            )]
        )
    }
}

// MARK: - Supporting Types

struct VerseTapPayload {
    let book: String
    let chapter: Int
    let verse: Int
    
    var description: String {
        "\(book) \(chapter):\(verse)"
    }
}

extension Notification.Name {
    static let kairoVerseTapped = Notification.Name("kairoVerseTapped")
}
