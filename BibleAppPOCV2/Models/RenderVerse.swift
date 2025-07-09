import Foundation

struct RenderVerse {
    let key: VerseKey
    let attributedText: NSAttributedString
    var fitsOnPage: Bool = true
}

extension RenderVerse {
    func withFitStatus(_ fits: Bool) -> RenderVerse {
        var copy = self
        copy.fitsOnPage = fits
        return copy
    }
}
