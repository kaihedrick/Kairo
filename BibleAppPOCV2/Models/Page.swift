// filepath: BibleAppPOCV2/Models/Page.swift
import Foundation

/// Represents a page of Bible content with navigation information
struct Page: Identifiable {
    let id = UUID()
    let attributedText: AttributedString
    let firstVerseKey: VerseKey
    let lastVerseKey: VerseKey
}
