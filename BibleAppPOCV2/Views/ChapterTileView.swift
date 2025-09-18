// filepath: BibleAppPOCV2/Views/ChapterTileView.swift
import SwiftUI

struct ChapterTileView: View {
    let chapterNumber: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .stroke(.primary.opacity(0.15), lineWidth: 0.5)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                .frame(width: 50, height: 50)

            Text("\(chapterNumber)")
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundStyle(.primary)
        }
        .frame(width: 50, height: 50)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
