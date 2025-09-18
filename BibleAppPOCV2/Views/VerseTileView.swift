// filepath: BibleAppPOCV2/Views/VerseTileView.swift
import SwiftUI

struct VerseTileView: View {
    let verseNumber: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .stroke(.primary.opacity(0.15), lineWidth: 0.5)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                .frame(width: 50, height: 50)

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
        }
        .frame(width: 50, height: 50)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
