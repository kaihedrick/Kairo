import SwiftUI

struct ChapterNumberView: View {
    let chapterNumber: Int
    
    var body: some View {
        Text("\(chapterNumber)")
            .font(.system(size: 38, weight: .bold))
            .foregroundColor(.primary.opacity(0.85))
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                    .background(Color.secondary.opacity(0.05))
            )
            .padding(.trailing, 6)
    }
}

// Text wrapping utility
extension View {
    func withChapterMark(_ chapterNumber: Int, isVisible: Bool) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if isVisible {
                ChapterNumberView(chapterNumber: chapterNumber)
            }
            self
        }
    }
}