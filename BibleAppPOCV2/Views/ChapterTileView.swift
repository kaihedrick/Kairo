// filepath: BibleAppPOCV2/Views/ChapterTileView.swift
import SwiftUI

struct ChapterTileView: View {
    let chapterNumber: Int

    var body: some View {
        Text("\(chapterNumber)")
            .font(.system(size: 18, weight: .bold, design: .default))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
    }
}

#Preview {
    VStack {
        ChapterTileView(chapterNumber: 1)
            .frame(width: 60, height: 60)
            .glassTile(cornerRadius: 12, id: "chapter-1", namespace: Namespace().wrappedValue)

        ChapterTileView(chapterNumber: 25)
            .frame(width: 60, height: 60)
            .glassTile(cornerRadius: 12, id: "chapter-25", namespace: Namespace().wrappedValue)
    }
    .padding()
}
