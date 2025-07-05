import Foundation
import SwiftUI
import CoreGraphics

actor PageCache {
    private let lru = LRUCache<VerseKey, OptimizedPageSlice>(capacity: 15)
    var keys: [VerseKey] { lru.keys }
    func get(_ k: VerseKey) -> OptimizedPageSlice? { lru.get(k) }
    func set(_ key: VerseKey, _ slice: OptimizedPageSlice) { lru.set(key, slice) }
    func remove(_ k: VerseKey) { lru.remove(k) }
    func clear() { lru.clear() }
}

final class PageNode {
    let key: VerseKey
    let slice: OptimizedPageSlice
    weak var prev: PageNode?
    weak var next: PageNode?
    init(key: VerseKey, slice: OptimizedPageSlice) {
        self.key = key
        self.slice = slice
    }
}

/// Errors that can occur while generating a page.
enum PageGenerationError: LocalizedError {
    case missingChapter(VerseKey)
    case layoutFailed(VerseKey)

    var errorDescription: String? {
        switch self {
        case .missingChapter(let key):
            return "Missing chapter for \(key.book) \(key.chapter)"
        case .layoutFailed(let key):
            return "Could not layout verse at \(key.book) \(key.chapter):\(key.verse)"
        }
    }
}

@MainActor
final class OnDemandPageGenerator: ObservableObject {
    @Published private(set) var currentPage: OptimizedPageSlice?
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?

    private let cache = PageCache()
    private let loader = OptimizedBibleDataLoader.shared
    private var size: CGSize
    private var currentNode: PageNode?
    private var pending: (key: VerseKey, text: AttributedString)?

    init(pageSize: CGSize) { self.size = pageSize }

    /// Update the size used for pagination and clear stale state.
    func updatePageSize(_ new: CGSize) {
        guard size != new else { return }
        size = new
        pending = nil
        currentNode = nil
        currentPage = nil
        Task { await cache.clear() }
    }

    func generatePage(startingAt verse: (book: String, chapter: Int, verse: Int)) async {
        let key = VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse)
        lastError = nil
        isGenerating = true
        defer {
            isGenerating = false
            Task { await trimCacheToThreePages() }
        }

        if let node = currentNode, node.key == key {
            currentNode = node
            currentPage = node.slice
            return
        } else if let node = currentNode?.next, node.key == key {
            currentNode = node
            currentPage = node.slice
            return
        } else if let node = currentNode?.prev, node.key == key {
            currentNode = node
            currentPage = node.slice
            return
        }

        if pending == nil, let cached = await cache.get(key) {
            let newNode = PageNode(key: key, slice: cached)
            currentNode?.next = newNode
            newNode.prev = currentNode
            currentNode = newNode
            await commitCurrentPage(cached, key: key)
            trimLinkedList()
            currentPage = cached
            return
        }

        let tail = (pending?.key == key) ? pending?.text : nil
        pending = nil
        switch await generatePageContent(startingAt: key, tail: tail) {
        case .success(let result):
            let slice = result.page.toOptimizedPageSlice()
            currentPage = slice
            pending = result.remainder
            let newNode = PageNode(key: key, slice: slice)
            currentNode?.next = newNode
            newNode.prev = currentNode
            currentNode = newNode
            await commitCurrentPage(slice, key: key)
            trimLinkedList()
        case .failure(let error):
            currentPage = nil
            lastError = error.localizedDescription
        }
    }

    func generateNextPage() async {
        defer { Task { await trimCacheToThreePages() } }
        if let node = currentNode?.next {
            currentNode = node
            currentPage = node.slice
            pending = nil
            return
        }
        if let remain = pending {
            await generatePage(startingAt: (remain.key.book, remain.key.chapter, remain.key.verse))
            return
        }
        guard let last = currentNode?.slice.endVerse,
              let next = await findNextVerse(after: last) else { return }
        await generatePage(startingAt: (next.book, next.chapter, next.verse))
    }

    func generatePreviousPage() async {
        defer { Task { await trimCacheToThreePages() } }
        if let node = currentNode?.prev {
            currentNode = node
            currentPage = node.slice
            pending = nil
            return
        }
        guard let first = currentNode?.slice.startVerse,
              let prev = await findPreviousVerse(before: first) else { return }
        await generatePage(startingAt: (prev.book, prev.chapter, prev.verse))
    }

    func handleMemoryPressure() {
        Task { await cache.clear() }
        JITTextFormatter.clearCache()
        autoreleasepool { }
    }

    func debugInfo() async -> String {
        let keys = await cache.keys
        return "cur=\(currentNode?.key.description ?? "nil") pending=\(pending?.key.description ?? "nil") cache=\(keys)"
    }

    private func commitCurrentPage(_ slice: OptimizedPageSlice, key: VerseKey) async {
        await cache.set(key, slice)
        await trimCacheToThreePages()
        let keys = await cache.keys
        if let cur = currentNode {
            print("cache keys:\t", keys)
            print("linked list: prev \(cur.prev != nil) – next \(cur.next != nil)")
        }
    }

    /// Append a verse key only after the text is committed to the page.
    private func commit(
        verseKey: VerseKey,
        newContent: AttributedString,
        currentContent: inout AttributedString,
        verseKeys: inout [VerseKey]
    ) {
        currentContent = newContent
        if verseKeys.last != verseKey { verseKeys.append(verseKey) }
    }

    private func trimCacheToThreePages() async {
        let allowed: Set<VerseKey> = [currentNode?.prev?.key, currentNode?.key, currentNode?.next?.key].compactMap { $0 }
        let keys = await cache.keys
        for k in keys where !allowed.contains(k) {
            await cache.remove(k)
        }
    }

    private func trimLinkedList() {
        guard let cur = currentNode else { return }
        if let p2 = cur.prev?.prev { p2.next = nil; p2.prev = nil }
        if let n2 = cur.next?.next { n2.prev = nil; n2.next = nil }
    }

    private func generatePageContent(
        startingAt key: VerseKey,
        tail: AttributedString?
    ) async -> Result<(page: GeneratedPage, remainder: (key: VerseKey, text: AttributedString)?), PageGenerationError> {
        guard let chapter = await loader.loadChapterContent(book: key.book, chapter: key.chapter) else {
            return .failure(.missingChapter(key))
        }
        let availW = max(size.width - LayoutMetrics.horizontalPagePadding * 2, 0)
        let availH = max(size.height - LayoutMetrics.verticalPagePadding * 2, 0)
        guard availW > 0 && availH > 0 else { return .failure(.layoutFailed(key)) }
        var idx = chapter.verses.firstIndex { $0.verse == key.verse } ?? 0
        var segments: [PageSegment] = []
        var curH: CGFloat = 0
        var currentContent = AttributedString()
        var verseKeys: [VerseKey] = []

        if var rest = tail, !rest.characters.isEmpty {
            let m = TextMeasurer.measure(rest, size: CGSize(width: availW, height: .greatestFiniteMagnitude))
            if m.height > availH {
                let parts = TextMeasurer.split(rest, size: CGSize(width: availW, height: availH))
                let newContent = currentContent + parts.0
                commit(verseKey: key, newContent: newContent, currentContent: &currentContent, verseKeys: &verseKeys)
                segments.append(PageSegment(attributed: parts.0, verseKey: key, isSplit: true))
                let page = GeneratedPage(segments: segments, startKey: key, navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false))
                return .success((page: page, remainder: (key, parts.1)))
            } else {
                let newContent = currentContent + rest
                commit(verseKey: key, newContent: newContent, currentContent: &currentContent, verseKeys: &verseKeys)
                segments.append(PageSegment(attributed: rest, verseKey: key, isSplit: true))
                curH = m.height
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

            let verseSizeFull = TextMeasurer.measure(formatted, size: CGSize(width: availW, height: .greatestFiniteMagnitude))
            if segments.isEmpty {
                print("MEASURE  verse\tH=\(verseSizeFull.height) budget=\(availH)")
            }

            if curH + verseSizeFull.height <= availH + 1 {
                let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse)
                let newContent = currentContent + formatted
                commit(verseKey: verseKey, newContent: newContent, currentContent: &currentContent, verseKeys: &verseKeys)
                segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
                curH += verseSizeFull.height
                idx += 1
                continue
            }

            // Verse does not fully fit
            if segments.isEmpty {
                let parts = TextMeasurer.split(formatted, size: CGSize(width: availW, height: availH))
                let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse)
                let newContent = currentContent + parts.0
                commit(verseKey: verseKey, newContent: newContent, currentContent: &currentContent, verseKeys: &verseKeys)
                segments.append(PageSegment(attributed: parts.0, verseKey: verseKey, isSplit: true))
                let page = GeneratedPage(segments: segments, startKey: key, navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false))
                return .success((page: page, remainder: (VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse), parts.1)))
            } else {
                let page = GeneratedPage(segments: segments, startKey: key, navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false))
                return .success((page: page, remainder: (VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse), formatted)))
            }
        }

        guard !segments.isEmpty else { return .failure(.layoutFailed(key)) }

        let page = GeneratedPage(segments: segments, startKey: key, navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false))
        return .success((page: page, remainder: nil))
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

    private func findPreviousVerse(before verse: VerseKey) async -> VerseKey? {
        if verse.verse > 1 {
            return VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse - 1)
        }
        guard let meta = await loader.metadata,
              let index = meta.books.firstIndex(where: { $0.name == verse.book }) else { return nil }
        if verse.chapter > 1 {
            let prevChapter = verse.chapter - 1
            guard let chapter = await loader.loadChapterContent(book: verse.book, chapter: prevChapter) else { return nil }
            return VerseKey(book: verse.book, chapter: prevChapter, verse: chapter.verses.count)
        }
        guard index > 0 else { return nil }
        let prevBook = meta.books[index - 1]
        let lastChapter = prevBook.chapterCount
        guard let chapter = await loader.loadChapterContent(book: prevBook.name, chapter: lastChapter) else { return nil }
        return VerseKey(book: prevBook.name, chapter: lastChapter, verse: chapter.verses.count)
    }
}
