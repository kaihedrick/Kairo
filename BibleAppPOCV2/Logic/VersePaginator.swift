import Foundation
import CoreGraphics

// Fits verses into a page based on height constraints
class VersePaginator {
    func paginate(verses: [RenderVerse], for size: CGSize) -> [RenderVerse] {
        var page: [RenderVerse] = []
        var height: CGFloat = 0

        for verse in verses {
            let verseHeight = TextMeasurer.measure(AttributedString(verse.attributedText), size: CGSize(width: size.width, height: .greatestFiniteMagnitude)).height
            if height + verseHeight > size.height {
                break
            }
            height += verseHeight
            page.append(verse)
        }

        return page
    }
}
