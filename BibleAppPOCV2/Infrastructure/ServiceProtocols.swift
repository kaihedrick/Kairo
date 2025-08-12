// filepath: BibleAppPOCV2/Infrastructure/ServiceProtocols.swift
import Foundation
import SwiftUI

// MARK: - Service Layer Protocols

/// Main Bible service protocol with all operations
protocol BibleServiceProtocol: Actor {
    func getMetadata() async -> ServiceResult<BibleMetadata>
    func loadChapter(book: String, chapter: Int) async -> ServiceResult<Chapter>
    func loadVerse(reference: VerseReference) async -> ServiceResult<Verse>
    func searchBooks(query: String) async -> ServiceResult<[BookMetadata]>
    func getNavigationContext(for reference: VerseReference) async -> ServiceResult<NavigationContext>
}

/// Page generation service protocol
protocol PageServiceProtocol: Actor {
    func generatePage(startingAt reference: VerseReference, pageSize: CGSize) async -> ServiceResult<PageContent>
    func getNextPage(from current: PageContent) async -> ServiceResult<PageContent?>
    func getPreviousPage(from current: PageContent) async -> ServiceResult<PageContent?>
}

/// Text formatting service protocol
protocol TextServiceProtocol {
    func formatVerse(_ verse: Verse, showChapterHeader: Bool, showBookTitle: Bool) -> AttributedString
    func measureText(_ text: AttributedString, containerSize: CGSize) -> CGSize
    func formatVerseRange(_ verses: [Verse]) -> AttributedString
}
