// filepath: BibleAppPOCV2/Models/Page.swift
import Foundation

struct Page: Identifiable {
    let id = UUID()
    let attributedText: AttributedString
    let firstVerseKey: VerseKey
    let lastVerseKey: VerseKey
}
