import SwiftUI

/// Fonts and spacing used by the Bible reader.
struct Typography {
    static let bookTitle = Font.system(size: 32, weight: .bold)
    static let chapter = Font.system(size: 28, weight: .bold)
    static let verseNumber = Font.system(size: 12, weight: .semibold)
    static let body = Font.body
    static let lineSpacing: CGFloat = 2
}
