// filepath: BibleAppPOCV2/Infrastructure/ServiceProtocols.swift
import Foundation
import SwiftUI

// MARK: - Service Layer Protocols

/// Result wrapper for service operations
enum ServiceResult<T> {
    case success(T)
    case failure(Error)
}

/// Main Bible service protocol with all operations
protocol BibleServiceProtocol: Actor {
    func getMetadata() async -> ServiceResult<DatabaseBibleMetadata>
    func loadChapter(book: String, chapter: Int) async -> ServiceResult<DatabaseChapter>
    func loadVerse(book: String, chapter: Int, verse: Int) async -> ServiceResult<DatabaseVerse>
    func searchBooks(query: String) async -> ServiceResult<[DatabaseBookMetadata]>
    func getNavigationContext(book: String, chapter: Int, verse: Int) async -> ServiceResult<DatabaseNavigationContext>
}

/// Page generation service protocol
protocol PageServiceProtocol: Actor {
    func generatePage(book: String, chapter: Int, verse: Int, pageSize: CGSize) async -> ServiceResult<DatabasePageContent>
    func getNextPage(from current: DatabasePageContent) async -> ServiceResult<DatabasePageContent?>
    func getPreviousPage(from current: DatabasePageContent) async -> ServiceResult<DatabasePageContent?>
}

/// Text formatting service protocol
protocol TextServiceProtocol {
    func formatVerse(_ verse: DatabaseVerse, showChapterHeader: Bool, showBookTitle: Bool) -> AttributedString
    func measureText(_ text: AttributedString, containerSize: CGSize) -> CGSize
    func formatVerseRange(_ verses: [DatabaseVerse]) -> AttributedString
}
