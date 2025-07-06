import Foundation
import CoreGraphics

class VerseRenderer {
    let paginator = VersePaginator()

    func render(verses: [RenderVerse], in size: CGSize) -> [RenderVerse] {
        let visible = paginator.paginate(verses: verses, for: size)
        DebugLogger.log("📄 Rendering \(visible.count) verses")
        return visible
    }
}
