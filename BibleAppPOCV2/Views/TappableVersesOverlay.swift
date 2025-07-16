import SwiftUI

struct TappableVersesOverlay: View {
    let page: OptimizedPageSlice
    let size: CGSize
    let onVerseTapped: (VerseKey) -> Void
    
    var body: some View {
        // Create a VStack with tappable areas for each verse
        VStack(alignment: .leading, spacing: 0) {
            ForEach(page.verseKeys, id: \.self) { verseKey in
                // For now, create equal height tap zones
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: estimatedVerseHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onVerseTapped(verseKey)
                    }
            }
        }
        .padding(.horizontal, LayoutMetrics.horizontalPagePadding)
        .padding(.vertical, LayoutMetrics.verticalPagePadding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
    
    private var estimatedVerseHeight: CGFloat {
        let availableHeight = size.height - (LayoutMetrics.verticalPagePadding * 2)
        let verseCount = max(1, page.verseKeys.count)
        return availableHeight / CGFloat(verseCount)
    }
}
