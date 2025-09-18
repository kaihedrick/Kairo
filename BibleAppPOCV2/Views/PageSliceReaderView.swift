// filepath: BibleAppPOCV2/Views/PageSliceReaderView.swift
// PageSliceReaderView.swift
// Reader view for OptimizedPageSlice with verseRuns

import SwiftUI
import Foundation

/// Reader view for OptimizedPageSlice with verseRuns
struct PageSliceReaderView: View {
    let page: OptimizedPageSlice
    let onVerseTapped: (VerseKey) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let runs = page.verseRunsForTapping, !runs.isEmpty {
                    ForEach(runs) { run in
                        VerseButtonView(
                            attributed: AttributedString(run.content),
                            onTap: { onVerseTapped(run.key) }
                        )
                    }
                } else {
                    // Fallback: infer using verseKeys in order and split by simple heuristics
                    // (Better to emit verseRuns at generation time.)
                    ForEach(Array(page.verseKeys.enumerated()), id: \.offset) { idx, key in
                        VerseButtonView(
                            attributed: sliceFor(key: key, in: page.content, isFirst: idx == 0),
                            onTap: { onVerseTapped(key) }
                        )
                    }
                }
            }
            .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
            .padding(.vertical, LayoutMetrics.verticalPagePadding)
        }
        .navigationTitle(page.navigationContext.isFirstVerseOfBook ? "\(page.startVerse.book)" : "\(page.startVerse.book) \(page.startVerse.chapter)")
    }
    
    // Simple fallback splitter: you can replace with stored offsets or injected markers
    private func sliceFor(key: VerseKey, in content: AttributedString, isFirst: Bool) -> AttributedString {
        // Without stored offsets, we can't perfectly slice.
        // Prefer `verseRuns`. As a minimal fallback, prepend the verse number + a best-effort body.
        var out = AttributedString("\(key.verse) ")
        out.font = Typography.verseNumber
        var body = AttributedString("…") // placeholder if you don't have exact offsets
        body.font = Typography.body
        out += body
        var spacer = AttributedString(" ")
        spacer.font = Typography.body
        out += spacer
        return out
    }
}
