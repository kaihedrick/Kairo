import Foundation
import SwiftUI

// MARK: - Service Layer Protocols

/// Main Bible service protocol with all operations
protocol BibleServiceProtocol: Actor {
    func getMetadata() async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.BibleMetadata>
    func loadChapter(book: String, chapter: Int) async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.Chapter>
    func loadVerse(reference: ImprovedBibleModels.VerseReference) async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.Verse>
    func searchBooks(query: String) async -> ImprovedBibleModels.ServiceResult<[ImprovedBibleModels.BookMetadata]>
    func getNavigationContext(for reference: ImprovedBibleModels.VerseReference) async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.NavigationContext>
}

/// Page generation service protocol
protocol PageServiceProtocol: Actor {
    func generatePage(startingAt reference: ImprovedBibleModels.VerseReference, pageSize: CGSize) async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.PageContent>
    func getNextPage(from current: ImprovedBibleModels.PageContent) async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.PageContent?>
    func getPreviousPage(from current: ImprovedBibleModels.PageContent) async -> ImprovedBibleModels.ServiceResult<ImprovedBibleModels.PageContent?>
}

/// Text formatting service protocol
protocol TextServiceProtocol {
    func formatVerse(_ verse: ImprovedBibleModels.Verse, showChapterHeader: Bool, showBookTitle: Bool) -> AttributedString
    func measureText(_ text: AttributedString, containerSize: CGSize) -> CGSize
    func formatVerseRange(_ verses: [ImprovedBibleModels.Verse]) -> AttributedString
}
