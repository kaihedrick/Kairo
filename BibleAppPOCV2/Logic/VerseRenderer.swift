import Foundation
import CoreGraphics

class VerseRenderer {
    let paginator = VersePaginator()

    func render(verses: [Verse], in size: CGSize) -> [Verse] {
        let visible = paginator.paginate(verses: verses, for: size)
        DebugLogger.log("📄 Rendering \(visible.count) verses")
        return visible
    }
}
