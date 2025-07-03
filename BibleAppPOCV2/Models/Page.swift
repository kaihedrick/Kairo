struct Page: Identifiable {
    let id = UUID()
    let attributedText: AttributedString
    let firstVerseKey: VerseKey
    let lastVerseKey: VerseKey
}
