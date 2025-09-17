// filepath: BibleAppPOCV2/Views/VerseTileView.swift
import SwiftUI

struct VerseTileView: View {
    let verseNumber: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(verseNumber)")
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("Verse")
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
        VerseTileView(verseNumber: 1)
            .frame(width: 60, height: 60)
            .glassTile(cornerRadius: 12, id: "verse-1", namespace: Namespace().wrappedValue)

        VerseTileView(verseNumber: 25)
            .frame(width: 60, height: 60)
            .glassTile(cornerRadius: 12, id: "verse-25", namespace: Namespace().wrappedValue)
    }
    .padding()
}
