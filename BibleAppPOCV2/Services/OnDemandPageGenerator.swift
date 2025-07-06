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
        let oldSize = size
        size = new
        
        // Clear ALL cached state since layout calculations are now invalid
        pending = nil
        currentNode = nil
        currentPage = nil
        
        // Force clear text formatter cache too
        JITTextFormatter.clearCache()
        
        Task { 
            await cache.clear() 
            print("📐 Page size updated from \(oldSize) to \(new), ALL caches cleared")
        }
    }

    func generatePage(startingAt verse: (book: String, chapter: Int, verse: Int)) async {
        let key = VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse)
        lastError = nil
        
        // Prevent duplicate generation if we're already generating this key
        if isGenerating {
            print("⚠️ Already generating page, skipping duplicate request for \(key.description)")
            return
        }
        
        // Check if we already have this page loaded
        if let current = currentPage, current.startVerse == key {
            print("✅ Page \(key.description) already loaded, skipping generation")
            return
        }
        
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
        
        // Check if we have a cached next page in the linked list
        if let node = currentNode?.next {
            currentNode = node
            currentPage = node.slice
            pending = nil
            return
        }
        
        // Priority 1: Handle pending remainder from current page
        if let remain = pending {
            await generatePage(startingAt: (remain.key.book, remain.key.chapter, remain.key.verse))
            return
        }
        
        // Priority 2: Find the next verse after the current page's end
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

    /// Handle memory pressure by clearing caches
    func handleMemoryPressure() {
        Task {
            await cache.clear()
            print("🧹 Memory pressure: Cleared page cache")
        }
    }

    /// Report content overflow for debugging
    func reportOverflow(actualHeight: CGFloat, availableHeight: CGFloat, segmentCount: Int) {
        print("📊 OVERFLOW REPORT:")
        print("   Actual height: \(actualHeight)")
        print("   Available height: \(availableHeight)")  
        print("   Overflow by: \(actualHeight - availableHeight)")
        print("   Segment count: \(segmentCount)")
        print("   Page size: \(size)")
        
        // This is mainly for debugging - we don't auto-regenerate to avoid loops
        // The user can swipe to regenerate if needed
    }
    
    /// Debug information about current state
    func debugInfo() async -> String {
        let cacheKeys = await cache.keys
        return """
        📊 PAGE GENERATOR DEBUG:
        Current page: \(currentPage?.startVerse.description ?? "none") - \(currentPage?.endVerse.description ?? "none")
        Page size: \(size)
        Cache keys: \(cacheKeys.map { $0.description }.joined(separator: ", "))
        Is generating: \(isGenerating)
        Has pending: \(pending != nil)
        """
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
        let allowed: Set<VerseKey> = Set([currentNode?.prev?.key, currentNode?.key, currentNode?.next?.key].compactMap { $0 })
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
        // compute available space
        let availW = max(size.width - LayoutMetrics.horizontalPagePadding * 2, 0)
        let availH = max(size.height - LayoutMetrics.verticalPagePadding * 2, 0)
        guard availW > 0 && availH > 0 else { return .failure(.layoutFailed(key)) }
        
        // Debug: Print budget calculation
        print("💰 Budget calc: inputSize=\(size), availW=\(availW), availH=\(availH), hPad=\(LayoutMetrics.horizontalPagePadding), vPad=\(LayoutMetrics.verticalPagePadding)")
        
        var idx = chapter.verses.firstIndex { $0.verse == key.verse } ?? 0
        var segments: [PageSegment] = []
        var curH: CGFloat = 0
        var currentContent = AttributedString()
        var verseKeys: [VerseKey] = []

        // Handle carry-over text from previous page
        if let rest = tail, !rest.characters.isEmpty {
            print("🔄 Processing tail for \(key.description)")
            let m = TextMeasurer.measure(rest, size: CGSize(width: availW, height: .greatestFiniteMagnitude))
            if m.height > availH {
                let parts = TextMeasurer.split(rest, size: CGSize(width: availW, height: availH))
                let newContent = currentContent + parts.0
                commit(verseKey: key, newContent: newContent, currentContent: &currentContent, verseKeys: &verseKeys)
                segments.append(PageSegment(attributed: parts.0, verseKey: key, isSplit: true))
                let startVisible = verseKeys.first ?? key
                let endVisible = verseKeys.last ?? key
                let page = GeneratedPage(
                    segments: segments,
                    startKey: key,
                    navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false),
                    startVisibleVerse: startVisible,
                    endVisibleVerse: endVisible
                )
                print("📄 Tail split again - page with tail partial, remainder still pending")
                return .success((page: page, remainder: (key, parts.1)))
            } else {
                let newContent = currentContent + rest
                commit(verseKey: key, newContent: newContent, currentContent: &currentContent, verseKeys: &verseKeys)
                segments.append(PageSegment(attributed: rest, verseKey: key, isSplit: true))
                curH = m.height
                print("✅ Tail consumed for \(key.description), verse count: \(verseKeys.count)")
                // Important: Move to next verse only after consuming the tail
                idx += 1
            }
        }

        // Process verses sequentially
        while idx < chapter.verses.count {
            let verse = chapter.verses[idx]
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse)
            
            let formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verse,
                text: verse.text,
                showChapterHeader: verse.verse == 1 && segments.isEmpty,
                showBookTitle: key.chapter == 1 && verse.verse == 1 && segments.isEmpty)

            let candidateContent = currentContent + formatted
            
            // Use debug measurement for better visibility
            let padding = EdgeInsets(
                top: LayoutMetrics.verticalPagePadding,
                leading: LayoutMetrics.horizontalPagePadding,
                bottom: LayoutMetrics.verticalPagePadding,
                trailing: LayoutMetrics.horizontalPagePadding
            )
            
            #if DEBUG
            let (actualSize, _) = JITTextFormatter.debugMeasurement(
                candidateContent,
                containerSize: size,
                padding: padding
            )
            #else
            let actualSize = JITTextFormatter.measureActualRender(
                candidateContent,
                containerSize: size,
                padding: padding
            )
            #endif
            
            // Debug: Print every 10 verses to see the height progression
            if verseKeys.count % 10 == 0 || verseKeys.count < 3 {
                print("📏 Verse \(verseKey.description): actualH=\(actualSize.height) vs containerH=\(size.height)")
            }

            // Check if the ACTUAL rendered size fits in the container
            if actualSize.height <= size.height {
                // fits on this page
                currentContent = candidateContent
                curH = actualSize.height
                if verseKeys.last != verseKey { verseKeys.append(verseKey) }
                segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
                idx += 1 // Move to next verse
                print("✅ Added complete verse \(verseKey.description) - total verses: \(verseKeys.count)")

            } else {
                // split the verse exactly at the remaining space
                let remainingSpace = max(size.height - curH, 0)
                let availW = max(size.width - LayoutMetrics.horizontalPagePadding * 2, 0)
                let parts = JITTextFormatter.split(
                    attributed: formatted,
                    maxSize: CGSize(width: availW, height: remainingSpace)
                )

                // parts.0 is what fits, parts.1 is the tail
                if !parts.0.characters.isEmpty {
                    currentContent += parts.0
                    if verseKeys.last != verseKey { verseKeys.append(verseKey) }
                    segments.append(PageSegment(attributed: parts.0, verseKey: verseKey, isSplit: true))
                    print("🔄 Split verse \(verseKey.description) - partial added, remainder pending")
                }

        let startVisible = verseKeys.first ?? key
        let endVisible = verseKeys.last ?? key
        let page = GeneratedPage(
            segments: segments,
            startKey: key,
            navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false),
            startVisibleVerse: startVisible,
            endVisibleVerse: endVisible
        )
        let remainder = parts.1.characters.isEmpty ? nil : (key: verseKey, text: parts.1)
        
        print("📄 Page complete: \(segments.count) segments, verses \(verseKeys.first?.description ?? "nil") to \(verseKeys.last?.description ?? "nil")")
        
        // Final validation: check if the complete page content actually fits
        let finalContent = page.segments.reduce(AttributedString()) { result, segment in
            result + segment.attributed
        }
        let finalSize = JITTextFormatter.measureActualRender(
            finalContent,
            containerSize: size,
            padding: EdgeInsets(
                top: LayoutMetrics.verticalPagePadding,
                leading: LayoutMetrics.horizontalPagePadding,
                bottom: LayoutMetrics.verticalPagePadding,
                trailing: LayoutMetrics.horizontalPagePadding
            )
        )
        
        if finalSize.height > size.height + 10 { // 10pt tolerance
            print("⚠️ FINAL VALIDATION: Page content (\(finalSize.height)) exceeds container (\(size.height))")
            print("🔍 Consider reducing verse count or improving splitting logic")
        } else {
            print("✅ FINAL VALIDATION: Page content fits perfectly (\(finalSize.height) <= \(size.height))")
        }
        
        return .success((page: page, remainder: remainder))
            }
        }

        // Fallback: if no segments were created, force at least one verse
        if segments.isEmpty && idx < chapter.verses.count {
            let verse = chapter.verses[idx]
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse)
            let formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verse,
                text: verse.text,
                showChapterHeader: verse.verse == 1,
                showBookTitle: key.chapter == 1 && verse.verse == 1)
            
            let newContent = currentContent + formatted
            commit(verseKey: verseKey, newContent: newContent, currentContent: &currentContent, verseKeys: &verseKeys)
            segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
        }

        guard !segments.isEmpty else { return .failure(.layoutFailed(key)) }

        let startVisible = verseKeys.first ?? key
        let endVisible = verseKeys.last ?? key
        let page = GeneratedPage(
            segments: segments,
            startKey: key,
            navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false),
            startVisibleVerse: startVisible,
            endVisibleVerse: endVisible
        )
        
        // Final validation: check if the complete page content actually fits
        let finalContent = page.segments.reduce(AttributedString()) { result, segment in
            result + segment.attributed
        }
        let finalSize = JITTextFormatter.measureActualRender(
            finalContent,
            containerSize: size,
            padding: EdgeInsets(
                top: LayoutMetrics.verticalPagePadding,
                leading: LayoutMetrics.horizontalPagePadding,
                bottom: LayoutMetrics.verticalPagePadding,
                trailing: LayoutMetrics.horizontalPagePadding
            )
        )
        
        if finalSize.height > size.height + 10 { // 10pt tolerance
            print("⚠️ FINAL VALIDATION: Page content (\(finalSize.height)) exceeds container (\(size.height))")
            print("🔍 Consider reducing verse count or improving splitting logic")
        } else {
            print("✅ FINAL VALIDATION: Page content fits perfectly (\(finalSize.height) <= \(size.height))")
        }
        
        return .success((page: page, remainder: nil))
    }

    private func findNextVerse(after verse: VerseKey) async -> VerseKey? {
        guard let chapter = await loader.loadChapterContent(book: verse.book, chapter: verse.chapter) else { return nil }
        
        // Find the current verse in the chapter's verse array
        if let currentIndex = chapter.verses.firstIndex(where: { $0.verse == verse.verse }) {
            // Check if there's a next verse in the same chapter
            let nextIndex = currentIndex + 1
            if nextIndex < chapter.verses.count {
                let nextVerse = chapter.verses[nextIndex]
                let result = VerseKey(book: verse.book, chapter: verse.chapter, verse: nextVerse.verse)
                print("🔍 findNextVerse: \(verse.description) → \(result.description) (same chapter)")
                return result
            }
        }
        
        // No more verses in current chapter, try next chapter
        guard let meta = await loader.metadata,
              let bookIndex = meta.books.firstIndex(where: { $0.name == verse.book }) else { return nil }
        
        // Try next chapter in same book
        if verse.chapter < meta.books[bookIndex].chapterCount {
            let result = VerseKey(book: verse.book, chapter: verse.chapter + 1, verse: 1)
            print("🔍 findNextVerse: \(verse.description) → \(result.description) (next chapter)")
            return result
        }
        
        // Try first chapter of next book
        guard bookIndex + 1 < meta.books.count else { return nil }
        let nextBook = meta.books[bookIndex + 1].name
        let result = VerseKey(book: nextBook, chapter: 1, verse: 1)
        print("🔍 findNextVerse: \(verse.description) → \(result.description) (next book)")
        return result
    }

    private func findPreviousVerse(before verse: VerseKey) async -> VerseKey? {
        guard let chapter = await loader.loadChapterContent(book: verse.book, chapter: verse.chapter) else { return nil }
        
        // Find the current verse in the chapter's verse array
        if let currentIndex = chapter.verses.firstIndex(where: { $0.verse == verse.verse }) {
            // Check if there's a previous verse in the same chapter
            if currentIndex > 0 {
                let prevVerse = chapter.verses[currentIndex - 1]
                return VerseKey(book: verse.book, chapter: verse.chapter, verse: prevVerse.verse)
            }
        }
        
        // No previous verse in current chapter, try previous chapter
        guard let meta = await loader.metadata,
              let bookIndex = meta.books.firstIndex(where: { $0.name == verse.book }) else { return nil }
        
        // Try previous chapter in same book
        if verse.chapter > 1 {
            let prevChapter = verse.chapter - 1
            guard let prevChapterContent = await loader.loadChapterContent(book: verse.book, chapter: prevChapter) else { return nil }
            // Get the last verse of the previous chapter
            if let lastVerse = prevChapterContent.verses.last {
                return VerseKey(book: verse.book, chapter: prevChapter, verse: lastVerse.verse)
            }
        }
        
        // Try last chapter of previous book
        guard bookIndex > 0 else { return nil }
        let prevBook = meta.books[bookIndex - 1]
        let lastChapter = prevBook.chapterCount
        guard let lastChapterContent = await loader.loadChapterContent(book: prevBook.name, chapter: lastChapter) else { return nil }
        if let lastVerse = lastChapterContent.verses.last {
            return VerseKey(book: prevBook.name, chapter: lastChapter, verse: lastVerse.verse)
        }
        
        return nil
    }
}

