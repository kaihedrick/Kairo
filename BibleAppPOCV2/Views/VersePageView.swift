import SwiftUI

struct VersePageView: View {
    let verses: [Verse]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(verses, id: \.key) { verse in
                Text(verse.attributedText.string)
            }
        }
        .padding()
    }
}
