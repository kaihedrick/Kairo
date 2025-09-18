// filepath: BibleAppPOCV2/Views/BibleReaderViewV2.swift
// BibleReaderViewV2.swift
// Alternative reader view with per-verse buttons for exact tapping

import SwiftUI
import Foundation

/// Alternative reader view with per-verse buttons for exact tapping
struct BibleReaderViewV2: View {
    let chapter: DatabaseChapter
    let onVerseTapped: (VerseKey) -> Void
    
    @State private var textService = TextService()
    
    var body: some View {
        ScrollView {
            // A single flowing block visually, but each verse is its own button
            VStack(alignment: .leading, spacing: 0) {
                ForEach(chapter.verses) { verse in
                    VerseButtonView(
                        attributed: buildAttributedVerse(verse),
                        onTap: { 
                            onVerseTapped(VerseKey(
                                book: verse.book, 
                                chapter: verse.chapter, 
                                verse: verse.verseNumber
                            )) 
                        }
                    )
                }
            }
            .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
            .padding(.vertical, LayoutMetrics.verticalPagePadding)
        }
        .navigationTitle("\(chapter.name)")
    }
    
    private func buildAttributedVerse(_ verse: DatabaseVerse) -> AttributedString {
        textService.formatVerse(verse, showChapterHeader: false, showBookTitle: false)
    }
}
