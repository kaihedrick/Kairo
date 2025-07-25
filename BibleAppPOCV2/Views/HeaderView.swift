// filepath: BibleAppPOCV2/Views/HeaderView.swift
// filepath: BibleAppPOCV2/Views/HeaderView.swift
import SwiftUI

struct HeaderView: View {
    let startVerse: VerseKey?
    let endVerse: VerseKey?

    var body: some View {
        if let start = startVerse, let end = endVerse {
            Text("\(start.book) \(start.chapter):\(start.verse)–\(end.chapter):\(end.verse)")
                .font(.headline)
        } else {
            Text("")
        }
    }
}
