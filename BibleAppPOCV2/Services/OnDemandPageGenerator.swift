import Foundation
import SwiftUI

actor PageCache {
    private let lru = LRUCache<VerseKey, GeneratedPage>(capacity: 15)
    func get(_ k: VerseKey) -> GeneratedPage? { lru.get(k) }
    func put(_ p: GeneratedPage) { lru.set(p.startKey, p) }
    func clear() { lru.clear() }
}

@MainActor
final class OnDemandPageGenerator: ObservableObject {
    @Published private(set) var currentPage: GeneratedPage?
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?

    private let cache = PageCache()
    private let loader = OptimizedBibleDataLoader.shared
    private var size: CGSize
    private var history: [VerseKey] = []
    private var pending: (key: VerseKey, text: AttributedString)?

    init(pageSize: CGSize) { self.size = pageSize }

    func updatePageSize(_ new: CGSize) { size = new }

    func generatePage(startingAt verse: (book: String, chapter: Int, verse: Int)) async {
        let key = VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse)
        lastError = nil
        isGenerating = true
        defer { isGenerating = false }
        if pending == nil, let cached = await cache.get(key) {
            currentPage = cached
            if history.last != key { history.append(key) }
            return
        }
        let tail = (pending?.key == key) ? pending?.text : nil
        pending = nil
        guard let (page, rem) = await generatePageContent(startingAt: key, tail: tail) else {
            currentPage = nil
            lastError = "Could not generate page for \(key.book) \(key.chapter):\(key.verse)"
            return
        }
        currentPage = page
        if history.last != key { history.append(key) }
        pending = rem
        if rem == nil { await cache.put(page) }
    }

    func generateNextPage() async {
        if let remain = pending {
            await generatePage(startingAt: (remain.key.book, remain.key.chapter, remain.key.verse))
            return
        }
        guard let last = currentPage?.segments.last?.verseKey,
              let next = await findNextVerse(after: last) else { return }
        await generatePage(startingAt: (next.book, next.chapter, next.verse))
    }

    func generatePreviousPage() async {
        guard history.count >= 2 else { return }
        history.removeLast()
        let prev = history.last!
        await generatePage(startingAt: (prev.book, prev.chapter, prev.verse))
    }

    func handleMemoryPressure() {
        Task { await cache.clear() }
        JITTextFormatter.clearCache()
        autoreleasepool { }
    }

    private func generatePageContent(startingAt key: VerseKey, tail: AttributedString?) async -> (GeneratedPage, (key: VerseKey, text: AttributedString)?)? {
        guard let chapter = await loader.loadChapterContent(book: key.book, chapter: key.chapter) else { return nil }
        let availW = max(size.width - 32, 0)
        let availH = max(size.height - 24, 0)
        var idx = chapter.verses.firstIndex { $0.verse == key.verse } ?? 0
        var segments: [PageSegment] = []
        var curH: CGFloat = 0

        if var rest = tail, !rest.characters.isEmpty {
            let m = TextMeasurer.measure(rest, size: CGSize(width: availW, height: .greatestFiniteMagnitude))
            if m.height > availH {
                let (fit, remain) = TextMeasurer.split(rest, size: CGSize(width: availW, height: availH))
                segments.append(PageSegment(attributed: fit, verseKey: key))
                let page = GeneratedPage(segments: segments, startKey: key, navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false))
                return (page, (key, remain))
            } else {
                segments.append(PageSegment(attributed: rest, verseKey: key))
                curH += m.height
                idx += 1
            }
        }

        while idx < chapter.verses.count {
            let verse = chapter.verses[idx]
            let formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verse,
                text: verse.text,
                showChapterHeader: verse.verse == 1 && segments.isEmpty,
                showBookTitle: key.chapter == 1 && verse.verse == 1 && segments.isEmpty)
            let sz = TextMeasurer.measure(formatted, size: CGSize(width: availW, height: .greatestFiniteMagnitude))
            if curH + sz.height <= availH {
                segments.append(PageSegment(attributed: formatted, verseKey: VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse)))
                curH += sz.height
                idx += 1
            } else if segments.isEmpty {
                let (head, tailPart) = TextMeasurer.split(formatted, size: CGSize(width: availW, height: availH))
                segments.append(PageSegment(attributed: head, verseKey: VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse)))
                let page = GeneratedPage(segments: segments, startKey: key, navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false))
                return (page, (VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse), tailPart))
            } else {
                let page = GeneratedPage(segments: segments, startKey: key, navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false))
                return (page, (VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse), formatted))
            }
        }

        let page = GeneratedPage(segments: segments, startKey: key, navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false))
        return (page, nil)
    }

    private func findNextVerse(after verse: VerseKey) async -> VerseKey? {
        guard let chapter = await loader.loadChapterContent(book: verse.book, chapter: verse.chapter) else { return nil }
        if verse.verse < chapter.verses.count {
            return VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse + 1)
        }
        guard let meta = await loader.metadata,
              let index = meta.books.firstIndex(where: { $0.name == verse.book }) else { return nil }
        if verse.chapter < meta.books[index].chapterCount {
            return VerseKey(book: verse.book, chapter: verse.chapter + 1, verse: 1)
        }
        guard index + 1 < meta.books.count else { return nil }
        let nextBook = meta.books[index + 1].name
        return VerseKey(book: nextBook, chapter: 1, verse: 1)
    }
}
