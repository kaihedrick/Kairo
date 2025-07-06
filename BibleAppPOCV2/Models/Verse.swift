import Foundation

struct Verse {
    let key: VerseKey
    let attributedText: NSAttributedString
    var fitsOnPage: Bool = true
}

extension Verse {
    func withFitStatus(_ fits: Bool) -> Verse {
        var copy = self
        copy.fitsOnPage = fits
        return copy
    }
}
