// filepath: BibleAppPOCV2/Services/OnDemandPageGenerator.swift
import Foundation
import SwiftUI

/// Generator for creating fragmented pages from verses
class FragmentedPageGenerator {
    private let loader: DatabaseBibleDataLoader

    init(loader: DatabaseBibleDataLoader) {
        self.loader = loader
    }

    func generateFragmentedPage(book: String, chapter: Int, verse: Int) -> FragmentedPage {
        // Placeholder implementation
        return FragmentedPage(book: book, chapter: chapter, verse: verse)
    }

    func createVerseFragment(book: String, chapter: Int, verse: Int, text: String) -> VerseFragment {
        let reference = VerseKey(book: book, chapter: chapter, verse: verse)
        return VerseFragment(reference: reference.description, textFragment: text, isStartOfVerse: true, isEndOfVerse: true, fullVerseText: text, sequenceNumber: 0, totalFragments: 1)
    }

    func generateContent(startingAt key: VerseKey, pageSize: CGSize, fragmentPending: VerseFragment?) async throws -> (page: FragmentedPage, remainder: VerseFragment?, pendingFragment: VerseFragment?) {
        // Placeholder implementation - would generate actual page content
        let reference = VerseKey(book: key.book, chapter: key.chapter, verse: key.verse)
        let fragment = createVerseFragment(book: key.book, chapter: key.chapter, verse: key.verse, text: "")
        let page = FragmentedPage(
            fragments: [fragment],
            navTitle: key.description,
            startVerse: reference.description,
            endVerse: reference.description,
            content: AttributedString(""),
            measuredHeight: pageSize.height,
            availableHeight: pageSize.height
        )
        return (page: page, remainder: nil, pendingFragment: nil)
    }
}
import CoreGraphics

// Helper function to parse reference string to VerseKey
private func parseReference(_ reference: String) -> VerseKey? {
    let components = reference.split(separator: " ")
    guard components.count >= 2 else { return nil }

    let book = String(components[0])
    let chapterVerse = String(components[1]).split(separator: ":")
    guard chapterVerse.count == 2,
          let chapter = Int(chapterVerse[0]),
          let verse = Int(chapterVerse[1]) else { return nil }

    return VerseKey(book: book, chapter: chapter, verse: verse)
}

// Simple cache for OnDemandPageGenerator
private actor SliceCache {
    private var cache = [VerseKey: DatabasePageContent]()
    var keys: [VerseKey] { Array(cache.keys) }
    func get(_ k: VerseKey) -> DatabasePageContent? { cache[k] }
    func set(_ key: VerseKey, _ slice: DatabasePageContent) { cache[key] = slice }
    func remove(_ k: VerseKey) { cache.removeValue(forKey: k) }
    func clear() { cache.removeAll() }
}

// Simple node for OnDemandPageGenerator
private final class SliceNode {
    let key: VerseKey
    let slice: DatabasePageContent
    weak var prev: SliceNode?
    weak var next: SliceNode?
    init(key: VerseKey, slice: DatabasePageContent) {
        self.key = key
        self.slice = slice
    }
}

// MARK: - Page-Aware Navigation Data Structures

struct PageRange: Equatable, Hashable {
    let startVerse: Int
    let endVerse: Int

    var description: String {
        "\(startVerse)-\(endVerse)"
    }
}

struct ChapterKey: Hashable {
    let book: String
    let chapter: Int

    var description: String {
        "\(book) \(chapter)"
    }
}

struct ChapterPages {
    let key: ChapterKey
    let ranges: [PageRange]
    let verseHeights: [Int: CGFloat] // verseNumber → measured height

    var pageCount: Int { ranges.count }

    func pageIndex(containing verse: Int) -> Int {
        // Binary search to find the page containing a verse
        var lo = 0, hi = ranges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let range = ranges[mid]
            if verse < range.startVerse {
                hi = mid - 1
            } else if verse > range.endVerse {
                lo = mid + 1
            } else {
                return mid
            }
        }
        // If not found, return the closest valid index
        return max(min(lo, ranges.count - 1), 0)
    }

    func range(at index: Int) -> PageRange? {
        ranges.indices.contains(index) ? ranges[index] : nil
    }
}

struct Cursor {
    var book: String
    var chapter: Int
    var pageIndex: Int

    var chapterKey: ChapterKey {
        ChapterKey(book: book, chapter: chapter)
    }

    var description: String {
        "\(book) \(chapter) [\(pageIndex)]"
    }
}

final class PageCache {
    private var map: [ChapterKey: ChapterPages] = [:]
    private var order: [ChapterKey] = [] // LRU order
    let capacity = 6 // current, ±2 neighbors

    func get(_ key: ChapterKey) -> ChapterPages? {
        if let pages = map[key] {
            // Move to front of LRU order
            order.removeAll { $0 == key }
            order.insert(key, at: 0)
            return pages
        }
        return nil
    }

    func put(_ pages: ChapterPages) {
        map[pages.key] = pages
        order.removeAll { $0 == pages.key }
        order.insert(pages.key, at: 0)

        // Evict if over capacity
        while order.count > capacity, let evicted = order.popLast() {
            map.removeValue(forKey: evicted)
            #if DEBUG
            print("📚 CACHE EVICT: \(evicted.description)")
            #endif
        }

        #if DEBUG
        print("📚 CACHE PUT: \(pages.key.description) → pages=\(pages.pageCount)")
        #endif
    }

    func clearAll() {
        map.removeAll()
        order.removeAll()
        #if DEBUG
        print("📚 CACHE CLEARED: All chapters evicted")
        #endif
    }

    var cacheSize: Int { map.count }
    var cachedChapters: [ChapterKey] { Array(map.keys) }

    // MARK: - Page Computation

    func computePages(book: String, chapter: Int, verses: [DatabaseVerse],
                     viewport: CGSize, limit: CGFloat = 0.90, safety: CGFloat = 20) -> ChapterPages {
        let maxAllowed = floor((viewport.height - safety) * limit)
        var ranges: [PageRange] = []
        var heights: [Int: CGFloat] = [:]

        #if DEBUG
        print("🧮 COMPUTING PAGES: \(book) \(chapter) (\(verses.count) verses), maxAllowed=\(String(format: "%.1f", maxAllowed))")
        #endif

        guard !verses.isEmpty else {
            return ChapterPages(key: ChapterKey(book: book, chapter: chapter), ranges: [], verseHeights: [:])
        }

        var startVerse = verses.first!.verseNumber
        var usedHeight: CGFloat = 0

        for verse in verses {
            // Format verse and measure height (simplified - use same logic as PageContentGenerator)
            let verseText = JITTextFormatter.formatVerse(
                book: book,
                chapter: chapter,
                verse: verse.verseNumber,
                text: verse.text,
                showChapterHeader: verse.verseNumber == 1,
                showBookTitle: chapter == 1 && verse.verseNumber == 1
            )

            let verseHeight = JITTextFormatter.measureText(verseText, maxSize: CGSize(
                width: viewport.width - (LayoutMetrics.horizontalPagePadding * 2),
                height: .greatestFiniteMagnitude
            )).height

            heights[verse.verseNumber] = verseHeight

            // Check if adding this verse would exceed the page limit
            if usedHeight + verseHeight > maxAllowed && usedHeight > 0 {
                // Complete current page and start new one
                let endVerse = verse.verseNumber - 1
                ranges.append(PageRange(startVerse: startVerse, endVerse: endVerse))

                #if DEBUG
                print("📄 PAGE COMPLETE: \(startVerse)-\(endVerse), height=\(String(format: "%.1f", usedHeight))")
                #endif

                startVerse = verse.verseNumber
                usedHeight = 0
            }

            usedHeight += verseHeight
        }

        // Add the final page if there are remaining verses
        if let lastVerse = verses.last?.verseNumber, startVerse <= lastVerse {
            ranges.append(PageRange(startVerse: startVerse, endVerse: lastVerse))

            #if DEBUG
            print("📄 FINAL PAGE: \(startVerse)-\(lastVerse), height=\(String(format: "%.1f", usedHeight))")
            print("📚 CHAPTER PAGES: \(book) \(chapter) → \(ranges.count) pages total")
            #endif
        }

        return ChapterPages(key: ChapterKey(book: book, chapter: chapter), ranges: ranges, verseHeights: heights)
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
    @Published private(set) var currentPage: DatabasePageContent?
    @Published private(set) var currentOptimizedPage: DatabasePageContent?
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?
    @Published private(set) var currentGeneratedPage: GeneratedPage?

    // MARK: - Page-Aware Navigation
    private var pageCache = PageCache()
    private var currentCursor: Cursor?

    private let cache = SliceCache()
    private let loader = DatabaseBibleDataLoader.shared
    private let historyManager = PageHistoryService()
    // Use the existing generation logic without FragmentedPageGenerator
    private var size: CGSize
    private var currentNode: SliceNode?
    private var pending: (key: VerseKey, text: AttributedString)?
    private var fragmentPending: String? // Changed from VerseFragment to simple string
    private var isNavigatingFromHistory = false

    init(pageSize: CGSize) { 
        self.size = pageSize 
        // Initialize without FragmentedPageGenerator
    }

    /// Update the size used for pagination and clear stale state.
    func updatePageSize(_ new: CGSize) {
        guard size != new else { return }
        let oldSize = size
        size = new
        
        // Clear ALL cached state since layout calculations are now invalid
        pending = nil
        currentNode = nil
        currentPage = nil
        currentGeneratedPage = nil
        currentOptimizedPage = nil
        
        // Clear enhanced page history since page layout has changed
        historyManager.clearHistory()
        
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

        #if DEBUG
        print("🚀 PAGE GENERATION REQUEST: \(key.description)")
        print("📍 REQUEST DETAILS: book='\(verse.book)', chapter=\(verse.chapter), verse=\(verse.verse)")
        #endif

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
            #if DEBUG
            print("✅ LINKED LIST: Page already current: \(node.key.description)")
            #endif
            currentNode = node
            currentPage = node.slice
            pending = nil
            #if DEBUG
            print("📖 LINKED LIST: Reused current node for \(key.description)")
            #endif
            return
        } else if let node = currentNode?.next, node.key == key {
            #if DEBUG
            print("✅ LINKED LIST: Found next page in linked list: \(node.key.description)")
            #endif
            currentNode = node
            currentPage = node.slice
            pending = nil
            #if DEBUG
            print("📖 LINKED LIST: Moved to next node for \(key.description)")
            #endif
            return
        } else if let node = currentNode?.prev, node.key == key {
            #if DEBUG
            print("✅ LINKED LIST: Found previous page in linked list: \(node.key.description)")
            #endif
            currentNode = node
            currentPage = node.slice
            pending = nil
            #if DEBUG
            print("📖 LINKED LIST: Moved to prev node for \(key.description)")
            print("🔙 After moving to prev - Current: \(currentNode?.key.description ?? "nil"), Prev: \(currentNode?.prev?.key.description ?? "nil"), Next: \(currentNode?.next?.key.description ?? "nil")")
            #endif
            return
        }

        if pending == nil, let cached = await cache.get(key) {
            #if DEBUG
            print("📚 CACHE: Found cached page for \(key.description)")
            #endif
            let newNode = SliceNode(key: key, slice: cached)

            // Properly link the new node into the doubly linked list
            if isNavigatingFromHistory {
                #if DEBUG
                print("📖 LINKED LIST: Setting up cache node during history navigation")
                #endif
                // When navigating from history, we need to be careful not to break the chain
                // Store the old current node to reconnect later
                if let oldNode = currentNode {
                    newNode.prev = oldNode
                    oldNode.next = newNode
                    #if DEBUG
                    print("📖 LINKED LIST: Connected cache node to old current node: \(oldNode.key.description) <-> \(key.description)")
                    #endif
                } else {
                    #if DEBUG
                    print("📖 LINKED LIST: No old current node during history navigation")
                    #endif
                }
            } else {
                #if DEBUG
                print("📖 LINKED LIST: Setting up cache node during normal navigation")
                #endif
                // Normal forward navigation
                if let oldNode = currentNode {
                    newNode.prev = oldNode
                    oldNode.next = newNode
                    #if DEBUG
                    print("📖 LINKED LIST: Connected cache node to current node: \(oldNode.key.description) -> \(key.description)")
                    #endif
                } else {
                    #if DEBUG
                    print("📖 LINKED LIST: No current node, this will be the first node")
                    #endif
                }
            }
            
            currentNode = newNode
            await commitCurrentPage(cached, key: key)
            trimLinkedList()
            currentPage = cached
            
            #if DEBUG
            // Debug log the linked list state
            print("📖 LINKED LIST: Loaded \(key.description), Prev: \(currentNode?.prev?.key.description ?? "nil"), Next: \(currentNode?.next?.key.description ?? "nil")")
            print("🔗 LINKED LIST STATE: \(debugLinkedList())")
            #endif
            return
        }

        // Only use pending tail if we're continuing the exact same verse that was cut off
        // Don't carry over tails from different verses/pages
        let tail = (pending?.key == key) ? pending?.text : nil
        pending = nil

        #if DEBUG
        if let tail = tail {
            print("📝 USING TAIL: \(tail.characters.count) characters from \(pending?.key.description ?? "unknown")")
        } else {
            print("📝 NO TAIL: Generating fresh page for \(key.description)")
        }
        #endif

        let result = await PageContentGenerator.generate(
            from: key,
            pageSize: size,
            tail: tail,
            using: loader
        )
        
        switch result {
        case .success(let generatedResult):
            let slice = generatedResult.page.toDatabasePageContent()
            currentPage = slice
            currentGeneratedPage = generatedResult.page
            pending = generatedResult.remainder

            #if DEBUG
            print("✅ PAGE GENERATED SUCCESSFULLY: \(slice.startVerse.description) to \(slice.endVerse.description)")
            print("📊 FINAL PAGE: \(slice.verseKeys.count) verses")
            let verseNumbers = slice.verseKeys.map { $0.verse }
            print("📋 FINAL VERSES: \(verseNumbers)")
            if let remainder = generatedResult.remainder {
                print("📄 REMAINDER: Next page starts at \(remainder.key.description)")
            } else {
                print("📄 REMAINDER: No remainder (end of chapter)")
            }
            #endif

            let newNode = SliceNode(key: key, slice: slice)
            
            // Properly link the new node into the doubly linked list
            if isNavigatingFromHistory {
                // When navigating from history, we need to be careful not to break the chain
                if let oldNode = currentNode {
                    newNode.prev = oldNode
                    oldNode.next = newNode
                }
                print("📖 LINKED LIST: Created new node from generation during history navigation")
            } else {
                // Normal forward navigation
                if let oldNode = currentNode {
                    newNode.prev = oldNode
                    oldNode.next = newNode
                }
                print("📖 LINKED LIST: Created new node from generation during normal navigation")
            }
            
            currentNode = newNode
            await commitCurrentPage(slice, key: key)
            trimLinkedList()
            
            // Add to history for backward navigation
            if !isNavigatingFromHistory {
                // TODO: Convert DatabasePageContent to OptimizedPageSlice for history tracking
                // historyManager.pushPage(slice: slice, pageSize: size)
                #if DEBUG
                print("📚 HISTORY TRACKING: Skipping history push for DatabasePageContent")
                #endif
            }
            
            #if DEBUG
            // Debug log the linked list state
            print("📖 LINKED LIST: Generated \(key.description), Prev: \(currentNode?.prev?.key.description ?? "nil"), Next: \(currentNode?.next?.key.description ?? "nil")")
            print("🔗 LINKED LIST STATE: \(debugLinkedList())")
            #endif
        case .failure(let error):
            currentPage = nil
            lastError = error.localizedDescription
        }
    }

    func generateNextPage() async {
        defer { Task { await trimCacheToThreePages() } }

        #if DEBUG
        print("➡️ FORWARD NAVIGATION: Starting forward navigation")
        print("➡️ Current node: \(currentNode?.key.description ?? "nil")")
        print("➡️ Current node next: \(currentNode?.next?.key.description ?? "nil")")
        #endif

        // Check if we have a cached next page in the linked list
        if let node = currentNode?.next {
            #if DEBUG
            print("✅ LINKED LIST: Found cached next page: \(node.key.description)")
            // Ensure the next node's prev pointer is correctly set
            if node.prev !== currentNode {
                print("🔗 LINKED LIST: Fixing broken prev pointer")
                node.prev = currentNode
            }
            #endif
            currentNode = node
            currentPage = node.slice
            pending = nil
            #if DEBUG
            print("➡️ After navigation - Current: \(currentNode?.key.description ?? "nil"), Prev: \(currentNode?.prev?.key.description ?? "nil"), Next: \(currentNode?.next?.key.description ?? "nil")")
            #endif
            return
        }

        #if DEBUG
        print("⚠️ LINKED LIST: No cached next page found, generating it now")
        #endif

        // Generate the next page since it doesn't exist in cache
        // Use page-based anchor calculation (endVerse + 1) instead of key-based (startVerse + 1)
        guard let currentSlice = currentNode?.slice else {
            print("❌ No current slice available for next page calculation")
            return
        }

        let nextVerse = currentSlice.endVerse.verse + 1
        let nextKey = VerseKey(book: currentSlice.endVerse.book,
                              chapter: currentSlice.endVerse.chapter,
                              verse: nextVerse)

        #if DEBUG
        print("🔍 LINKED LIST: Generating next page for: \(nextKey.description)")
        print("   Page-based anchor: \(currentSlice.endVerse.description) + 1 = \(nextKey.description)")
        #endif

        // Generate the next page by calling generatePage
        await generatePage(startingAt: (nextKey.book, nextKey.chapter, nextKey.verse))
    }

    func generatePreviousPage() async {
        defer { Task { await trimCacheToThreePages() } }

        #if DEBUG
        print("🔙 BACKWARD NAVIGATION: Starting backward navigation")
        print("🔙 Current node: \(currentNode?.key.description ?? "nil")")
        print("🔙 Current node prev: \(currentNode?.prev?.key.description ?? "nil")")
        print("🔙 Current node next: \(currentNode?.next?.key.description ?? "nil")")
        #endif

        // Check if we have a cached previous page in the linked list
        if let node = currentNode?.prev {
            #if DEBUG
            print("✅ LINKED LIST: Found cached previous page: \(node.key.description)")
            // Ensure the previous node's next pointer is correctly set
            if node.next !== currentNode {
                print("🔗 LINKED LIST: Fixing broken next pointer")
                node.next = currentNode
            }
            #endif
            currentNode = node
            currentPage = node.slice
            pending = nil
            #if DEBUG
            print("📖 LINKED LIST: Used cached previous page for \(node.key.description)")
            print("🔙 After navigation - Current: \(currentNode?.key.description ?? "nil"), Prev: \(currentNode?.prev?.key.description ?? "nil"), Next: \(currentNode?.next?.key.description ?? "nil")")
            #endif
            return
        }

        #if DEBUG
        print("⚠️ LINKED LIST: No cached previous page found, generating it now")
        #endif

        // Generate the previous page since it doesn't exist in cache
        if let currentKey = currentNode?.key,
           let previousKey = await findPreviousVerseKey(for: currentKey) {
            #if DEBUG
            print("🔍 LINKED LIST: Generating previous page for: \(previousKey.description)")
            #endif

            // Generate the previous page by calling generatePage
            await generatePage(startingAt: (previousKey.book, previousKey.chapter, previousKey.verse))
            return
        }

        #if DEBUG
        print("⚠️ LINKED LIST: No cached previous page found, falling back to history")
        #endif
        
        // Store the current node to reconnect after history navigation
        let oldNode = currentNode
        
        // Use enhanced history for reliable backward navigation
        if historyManager.canGoBackward, let historyEntry = historyManager.goBackward() {
            print("📚 LEGACY BACKWARD NAVIGATION: Using enhanced history")
            
            isNavigatingFromHistory = true
            defer { isNavigatingFromHistory = false }
            
            if await restorePageFromHistory(historyEntry) {
                // After restoring from history, reconnect the linked list
                if let oldNode = oldNode, let currentNode = currentNode {
                    currentNode.next = oldNode
                    oldNode.prev = currentNode
                    print("📖 LINKED LIST: Reconnected after history restore - Current: \(currentNode.key.description) -> Next: \(oldNode.key.description)")
                }
                return
            }
        }
        
        // NO FALLBACK: Legacy method should not guess page starts
        print("❌ LEGACY BACKWARD NAVIGATION: No reliable history available")
        lastError = "Cannot navigate backwards - no page history available"
    }

    // MARK: - Page-Aware Navigation Methods

    /// Navigate to the next page using cursor-based navigation
    func navigateToNextPage() async {
        guard let cursor = currentCursor else {
            #if DEBUG
            print("❌ CURSOR NAV: No current cursor")
            #endif
            return
        }

        let nextCursor = nextPageCursor(from: cursor)
        guard let nextCursor = nextCursor else {
            #if DEBUG
            print("❌ CURSOR NAV: No next page available")
            #endif
            return
        }

        #if DEBUG
        print("➡️ CURSOR NAV: \(cursor.description) → \(nextCursor.description)")
        #endif

        // Load the page for the new cursor
        await loadPageForCursor(nextCursor)
    }

    /// Navigate to the previous page using cursor-based navigation
    func navigateToPreviousPage() async {
        guard let cursor = currentCursor else {
            #if DEBUG
            print("❌ CURSOR NAV: No current cursor")
            #endif
            return
        }

        let prevCursor = previousPageCursor(from: cursor)
        guard let prevCursor = prevCursor else {
            #if DEBUG
            print("❌ CURSOR NAV: No previous page available")
            #endif
            return
        }

        #if DEBUG
        print("⬅️ CURSOR NAV: \(cursor.description) → \(prevCursor.description)")
        #endif

        // Load the page for the new cursor
        await loadPageForCursor(prevCursor)
    }

    /// Jump to a specific verse using page-aware navigation
    func jumpToVerse(book: String, chapter: Int, verse: Int) async {
        let chapterKey = ChapterKey(book: book, chapter: chapter)

        // Get or compute chapter pages
        var chapterPages = pageCache.get(chapterKey)
        if chapterPages == nil {
            let result = await loader.loadChapter(book: book, chapter: chapter)
            if case .success(let chapterData) = result {
                chapterPages = pageCache.computePages(
                    book: book,
                    chapter: chapter,
                    verses: chapterData.verses,
                    viewport: size
                )
                if let chapterPages = chapterPages {
                    pageCache.put(chapterPages)
                }
            }
        }

        guard let chapterPages = chapterPages else {
            #if DEBUG
            print("❌ JUMP: Could not load chapter \(chapterKey.description)")
            #endif
            return
        }

        // Find the page containing the target verse
        let pageIndex = chapterPages.pageIndex(containing: verse)
        let cursor = Cursor(book: book, chapter: chapter, pageIndex: pageIndex)

        #if DEBUG
        print("🎯 JUMP: verse=\(verse) → page=\(pageIndex) (\(chapterPages.ranges[pageIndex]))")
        #endif

        // Load the page for the cursor
        await loadPageForCursor(cursor)
    }

    // MARK: - Private Page-Aware Navigation Helpers

    private func nextPageCursor(from cursor: Cursor) -> Cursor? {
        let chapterKey = cursor.chapterKey

        guard let pages = pageCache.get(chapterKey) else {
            #if DEBUG
            print("❌ NEXT CURSOR: Chapter not cached \(chapterKey.description)")
            #endif
            return nil
        }

        if cursor.pageIndex + 1 < pages.pageCount {
            // Next page in same chapter
            return Cursor(book: cursor.book, chapter: cursor.chapter, pageIndex: cursor.pageIndex + 1)
        } else {
            // Cross-chapter: first page of next chapter
            return firstPageOfNextChapter(after: chapterKey)
        }
    }

    private func previousPageCursor(from cursor: Cursor) -> Cursor? {
        let chapterKey = cursor.chapterKey

        guard let pages = pageCache.get(chapterKey) else {
            #if DEBUG
            print("❌ PREV CURSOR: Chapter not cached \(chapterKey.description)")
            #endif
            return nil
        }

        if cursor.pageIndex > 0 {
            // Previous page in same chapter
            return Cursor(book: cursor.book, chapter: cursor.chapter, pageIndex: cursor.pageIndex - 1)
        } else {
            // Cross-chapter: last page of previous chapter
            return lastPageOfPreviousChapter(before: chapterKey)
        }
    }

    private func firstPageOfNextChapter(after chapterKey: ChapterKey) -> Cursor? {
        // Simplified - would need book metadata for proper chapter navigation
        // For now, return nil (end of content)
        return nil
    }

    private func lastPageOfPreviousChapter(before chapterKey: ChapterKey) -> Cursor? {
        // Simplified - would need book metadata for proper chapter navigation
        // For now, return nil (beginning of content)
        return nil
    }

    private func loadPageForCursor(_ cursor: Cursor) async {
        let chapterKey = cursor.chapterKey

        // Get or compute chapter pages
        var chapterPages = pageCache.get(chapterKey)
        if chapterPages == nil {
            let result = await loader.loadChapter(book: cursor.book, chapter: cursor.chapter)
            if case .success(let chapter) = result {
                chapterPages = pageCache.computePages(
                    book: cursor.book,
                    chapter: cursor.chapter,
                    verses: chapter.verses,
                    viewport: size
                )
                if let chapterPages = chapterPages {
                    pageCache.put(chapterPages)
                }
            }
        }

        guard let chapterPages = chapterPages,
              let pageRange = chapterPages.range(at: cursor.pageIndex) else {
            #if DEBUG
            print("❌ LOAD CURSOR: Could not get page range for \(cursor.description)")
            #endif
            return
        }

        #if DEBUG
        print("📖 LOADING PAGE: \(cursor.description) → verses \(pageRange.description)")
        #endif

        // Generate the page using the existing logic
        let verseKey = VerseKey(book: cursor.book, chapter: cursor.chapter, verse: pageRange.startVerse)
        await generatePage(startingAt: (cursor.book, cursor.chapter, pageRange.startVerse))

        // Update current cursor
        currentCursor = cursor
    }

    /// Handle memory pressure by clearing caches
    func handleMemoryPressure() {
        Task {
            await cache.clear()
            print("🧹 Memory pressure: Cleared page cache")
        }
    }

    /// Report overflow from SwiftUI for adaptive adjustment
    /// NOTE: With dynamic height measurement, overflow should be rare but we log it for debugging
    func reportOverflow(actualHeight: CGFloat, availableHeight: CGFloat, segmentCount: Int) {
        print("⚠️ UNEXPECTED OVERFLOW: actual=\(actualHeight), available=\(availableHeight), verses=\(segmentCount)")
        print("📝 This suggests our dynamic height measurement may need refinement")
        
        // REMOVED: adjustConservativeMultiplier call - no longer using prediction-based approach
        // The new dynamic height measurement should prevent overflow by measuring before adding verses
    }
    
    // REMOVED: adjustConservativeMultiplier method - legacy prediction-based approach
    // WHY: Dynamic height measurement eliminates need for conservative estimation
    // The new approach measures each verse before adding it to the page
    
    /// Debug information about current state
    func debugInfo() async -> String {
        let cacheKeys = await cache.keys
        let historyInfo = historyManager.getDebugInfo()
        return """
        📊 PAGE GENERATOR DEBUG:
        Current page: \(currentPage?.startVerse.description ?? "none") - \(currentPage?.endVerse.description ?? "none")
        Current optimized page: \(currentOptimizedPage?.navTitle ?? "none")
        Page size: \(size)
        Cache keys: \(cacheKeys.map { $0.description }.joined(separator: ", "))
        Is generating: \(isGenerating)
        Has pending: \(pending != nil)
        Is navigating from history: \(isNavigatingFromHistory)
        Can go to previous page: \(canGoToPreviousPage)
        Can go to next page: \(canGoToNextPage)
        \(historyInfo)
        """
    }
    
    private func commitCurrentPage(_ slice: DatabasePageContent, key: VerseKey) async {
        await cache.set(key, slice)
        await trimCacheToThreePages()
        #if DEBUG
        let keys = await cache.keys
        if let cur = currentNode {
            print("cache keys:\t", keys)
            print("linked list: prev \(cur.prev != nil) – next \(cur.next != nil)")
        }
        #endif
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
        // Skip trimming during history navigation to preserve valid SliceNodes
        if isNavigatingFromHistory {
            print("📖 CACHE: Skipping trim during history navigation")
            return
        }
        
        let allowed: Set<VerseKey> = Set([currentNode?.prev?.key, currentNode?.key, currentNode?.next?.key].compactMap { $0 })
        let keys = await cache.keys
        for k in keys where !allowed.contains(k) {
            await cache.remove(k)
        }
    }

    private func trimLinkedList() {
        guard let cur = currentNode else { return }

        #if DEBUG
        print("🔗 TRIM: Trimming linked list around current: \(cur.key.description)")
        print("🔗 TRIM: Before - Prev: \(cur.prev?.key.description ?? "nil"), Next: \(cur.next?.key.description ?? "nil")")
        print("🔗 TRIM: Before - Prev.Prev: \(cur.prev?.prev?.key.description ?? "nil"), Next.Next: \(cur.next?.next?.key.description ?? "nil")")
        #endif

        if let p2 = cur.prev?.prev {
            #if DEBUG
            print("🔗 TRIM: Disconnecting prev.prev: \(p2.key.description)")
            #endif
            p2.next = nil
            p2.prev = nil
        }
        if let n2 = cur.next?.next {
            #if DEBUG
            print("🔗 TRIM: Disconnecting next.next: \(n2.key.description)")
            #endif
            n2.prev = nil
            n2.next = nil
        }

        #if DEBUG
        print("🔗 TRIM: After - Prev: \(cur.prev?.key.description ?? "nil"), Next: \(cur.next?.key.description ?? "nil")")
        #endif
    }

    private func debugLinkedList() -> String {
        var result = "["
        var node = currentNode
        while let n = node?.prev {
            result = "\(n.key.description) <- " + result
            node = n
        }

        if let cur = currentNode {
            result += "[\(cur.key.description)]"
        }

        node = currentNode
        while let n = node?.next {
            result += " -> \(n.key.description)"
            node = n
        }

        result += "]"
        return result
    }

    private func findPreviousVerseKey(for verse: VerseKey) async -> VerseKey? {
        let result = await loader.loadChapter(book: verse.book, chapter: verse.chapter)
        guard case .success(let chapter) = result else { return nil }

        // Find the current verse in the chapter's verse array
        if let currentIndex = chapter.verses.firstIndex(where: { $0.verseNumber == verse.verse }) {
            // Check if there's a previous verse in the same chapter
            let previousIndex = currentIndex - 1
            if previousIndex >= 0 {
                let previousVerse = chapter.verses[previousIndex]
                return VerseKey(book: verse.book, chapter: verse.chapter, verse: previousVerse.verseNumber)
            }

            // No previous verse in current chapter, try previous chapter
            if verse.chapter > 1 {
                let previousChapter = verse.chapter - 1
                // Load the previous chapter to get its last verse
                let prevChapterResult = await loader.loadChapter(book: verse.book, chapter: previousChapter)
                if case .success(let prevChapter) = prevChapterResult, let lastVerse = prevChapter.verses.last {
                    return VerseKey(book: verse.book, chapter: previousChapter, verse: lastVerse.verseNumber)
                }
            }

            // Try last chapter of previous book
            guard let meta = await loader.metadata,
                  let bookIndex = meta.books.firstIndex(where: { $0.name == verse.book }) else {
                return nil
            }

            if bookIndex > 0 {
                let previousBook = meta.books[bookIndex - 1]
                let lastChapterResult = await loader.loadChapter(book: previousBook.name, chapter: previousBook.chapterCount)
                if case .success(let lastChapter) = lastChapterResult, let lastVerse = lastChapter.verses.last {
                    return VerseKey(book: previousBook.name, chapter: previousBook.chapterCount, verse: lastVerse.verseNumber)
                }
            }
        }

        return nil
    }

    private func findNextVerse(after verse: VerseKey) async -> VerseKey? {
        let result = await loader.loadChapter(book: verse.book, chapter: verse.chapter)
        guard case .success(let chapter) = result else { return nil }
        
        // Find the current verse in the chapter's verse array
        if let currentIndex = chapter.verses.firstIndex(where: { $0.verseNumber == verse.verse }) {
            // Check if there's a next verse in the same chapter
            let nextIndex = currentIndex + 1
            if nextIndex < chapter.verses.count {
                let nextVerse = chapter.verses[nextIndex]
                let nextVerseKey = VerseKey(book: verse.book, chapter: verse.chapter, verse: nextVerse.verseNumber)
                print("🔍 findNextVerse: \(verse.description) → \(nextVerseKey.description) (same chapter)")
                return nextVerseKey
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
        let nextBookKey = VerseKey(book: nextBook, chapter: 1, verse: 1)
        print("🔍 findNextVerse: \(verse.description) → \(nextBookKey.description) (next book)")
        return nextBookKey
    }

    private func findPreviousVerse(before verse: VerseKey) async -> VerseKey? {
        let result = await loader.loadChapter(book: verse.book, chapter: verse.chapter)
        guard case .success(let chapter) = result else { return nil }
        
        // Find the current verse in the chapter's verse array
        if let currentIndex = chapter.verses.firstIndex(where: { $0.verseNumber == verse.verse }) {
            // Check if there's a previous verse in the same chapter
            if currentIndex > 0 {
                let prevVerse = chapter.verses[currentIndex - 1]
                return VerseKey(book: verse.book, chapter: verse.chapter, verse: prevVerse.verseNumber)
            }
        }
        
        // No previous verse in current chapter, try previous chapter
        guard let meta = await loader.metadata,
              let bookIndex = meta.books.firstIndex(where: { $0.name == verse.book }) else { return nil }
        
        // Try previous chapter in same book
        if verse.chapter > 1 {
            let prevChapter = verse.chapter - 1
            let prevResult = await loader.loadChapter(book: verse.book, chapter: prevChapter)
            guard case .success(let prevChapterContent) = prevResult else { return nil }
            // Get the last verse of the previous chapter
            if let lastVerse = prevChapterContent.verses.last {
                return VerseKey(book: verse.book, chapter: prevChapter, verse: lastVerse.verseNumber)
            }
        }
        
        // Try last chapter of previous book
        guard bookIndex > 0 else { return nil }
        let prevBook = meta.books[bookIndex - 1]
        let lastChapter = prevBook.chapterCount
        let lastResult = await loader.loadChapter(book: prevBook.name, chapter: lastChapter)
        guard case .success(let lastChapterContent) = lastResult else { return nil }
        if let lastVerse = lastChapterContent.verses.last {
            return VerseKey(book: prevBook.name, chapter: lastChapter, verse: lastVerse.verseNumber)
        }
        
        return nil
    }
    
    /// Generate a page using the new fragment-based approach
    func generateOptimizedPage(startingAt verse: (book: String, chapter: Int, verse: Int)) async {
        let key = VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse)
        lastError = nil
        
        // Prevent duplicate generation if we're already generating this key
        if isGenerating {
            print("⚠️ Already generating fragmented page, skipping duplicate request for \(key.description)")
            return
        }
        
        // Check if we already have this page loaded
        if let current = currentOptimizedPage, current.startVerse.book == key.book && 
           current.startVerse.chapter == key.chapter && current.startVerse.verse == key.verse {
            print("✅ Fragmented page \(key.description) already loaded, skipping generation")
            return
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        // Generate page using existing logic
        await generatePage(startingAt: (key.book, key.chapter, key.verse))
        
        // Convert currentPage to DatabasePageContent
        if let generatedPage = currentGeneratedPage {
            currentOptimizedPage = generatedPage.toDatabasePageContent()
            fragmentPending = nil // Reset fragment pending
        }
        
        // Create and store history entry for reliable backward navigation
        if !isNavigatingFromHistory, let optimizedPage = currentOptimizedPage {
            // TODO: Convert DatabasePageContent to OptimizedPageSlice for history tracking
            // historyManager.pushOptimizedPage(optimizedPage, pageSize: size)
            print("📚 HISTORY TRACKING: Skipping history push for DatabasePageContent (\(historyManager.historyCount) total)")
        } else {
            print("📚 HISTORY TRACKING: Skipped adding page (navigating from history)")
        }
        
        if let optimizedPage = currentOptimizedPage {
            print("📖 OPTIMIZED PAGE GENERATED: \(optimizedPage.navTitle)")
        }
    }
    
    /// Navigate to next page with fragment support
    func generateNextOptimizedPage() async {
        defer { Task { await trimCacheToThreePages() } }
        
        // If we have a pending fragment text, clear it and generate next page normally
        if fragmentPending != nil {
            fragmentPending = nil // Clear pending fragment
            // Continue with normal next page generation
            return
        }
        
        // Find the next verse after the current page's end
        guard let current = currentOptimizedPage,
              let nextVerse = await findNextVerse(after: VerseKey(
                book: current.endVerse.book,
                chapter: current.endVerse.chapter,
                verse: current.endVerse.verse
              )) else { return }
        
        await generateOptimizedPage(startingAt: (nextVerse.book, nextVerse.chapter, nextVerse.verse))
    }
    
    /// Navigate to previous page with enhanced history - NO UNRELIABLE FALLBACK
    func generatePreviousOptimizedPage() async {
        defer { Task { await trimCacheToThreePages() } }
        
        // Store the current fragmented page for potential reconnection
        let oldOptimizedPage = currentOptimizedPage
        
        // Use enhanced history manager for reliable backward navigation
        if historyManager.canGoBackward, let historyEntry = historyManager.goBackward() {
            print("📚 BACKWARD NAVIGATION: Using enhanced history entry")
            
            // Set flag to prevent adding this page to history again
            isNavigatingFromHistory = true
            defer { isNavigatingFromHistory = false }
            
            // Restore page from history entry with exact layout reproduction
            if await restorePageFromHistory(historyEntry) {
                print("✅ BACKWARD NAVIGATION: Successfully restored exact page from history")
                
                // TODO: If we had a doubly linked list for fragmented pages, we would reconnect here
                // For now, we just ensure the page change is visible
                if let restoredPage = currentOptimizedPage,
                   let oldPage = oldOptimizedPage {
                    print("📖 FRAGMENTED PAGE: Navigated from \(oldPage.startVerse.book) \(oldPage.startVerse.chapter):\(oldPage.startVerse.verse) to \(restoredPage.startVerse.book) \(restoredPage.startVerse.chapter):\(restoredPage.startVerse.verse)")
                }
                
                return
            } else {
                print("❌ BACKWARD NAVIGATION: Failed to restore from history - this should not happen!")
                // Push the entry back since we failed to restore it
                historyManager.pushPageBack(historyEntry)
            }
        }
        
        // NO FALLBACK: If we can't restore from history, we can't reliably navigate backwards
        // This ensures we never show incorrect pages due to estimation errors
        print("❌ BACKWARD NAVIGATION: No reliable history available - cannot navigate backwards safely")
        print("💡 HINT: This usually means you're at the first page or history was cleared")
        
        // Optional: Could show user feedback that backward navigation is not available
        // For now, we simply don't navigate to avoid showing wrong content
        lastError = "Cannot navigate backwards - no page history available"
    }
    
    /// Navigate to next page using enhanced history if available
    func generateNextOptimizedPageWithHistory() async {
        defer { Task { await trimCacheToThreePages() } }
        
        // First, try to use enhanced history manager for forward navigation
        if historyManager.canGoForward, let historyEntry = historyManager.goForward() {
            print("📚 FORWARD NAVIGATION: Using enhanced history entry")
            
            // Set flag to prevent adding this page to history again
            isNavigatingFromHistory = true
            defer { isNavigatingFromHistory = false }
            
            // Restore page from history entry
            if await restorePageFromHistory(historyEntry) {
                print("✅ FORWARD NAVIGATION: Successfully restored page from history")
                return
            } else {
                print("❌ FORWARD NAVIGATION: Failed to restore from history, using regular navigation")
                // Push the entry back since we failed to restore it
                historyManager.pushPageBack(historyEntry)
            }
        }
        
        // Fallback to regular forward navigation with history tracking
        print("📚 FORWARD NAVIGATION: Using regular forward navigation with history tracking")
        await generateNextOptimizedPage()
    }
    
    /// Navigate to the next page of verses using the fragment-based approach
    func goToNextPage() async {
        print("📚 PAGE NAVIGATION: Going to next page")
        await generateNextOptimizedPageWithHistory()
    }
    
    /// Navigate back to the previous full page of verses using history snapshots
    func goToPreviousPage() async {
        print("📚 PAGE NAVIGATION: Going to previous page")
        await generatePreviousOptimizedPage()
    }
    
    /// Check if we can navigate to the next page
    var canGoToNextPage: Bool {
        // Can always try to generate next page unless we're at the very end of the Bible
        return true // TODO: Could add logic to check if we're at the last verse of Revelation
    }
    
    /// Check if we can navigate to the previous page - relies on reliable history only
    var canGoToPreviousPage: Bool {
        // RELIABLE BACKWARD NAVIGATION: Only allow if we have verified history
        return historyManager.canGoBackward
    }
    
    /// Restore a page from a history entry with exact layout reproduction
    private func restorePageFromHistory(_ entry: PageHistoryEntry) async -> Bool {
        // Verify layout compatibility
        guard entry.isCompatibleWith(
            pageSize: size,
            horizontalPadding: LayoutMetrics.horizontalPagePadding,
            verticalPadding: LayoutMetrics.verticalPagePadding
        ) else {
            print("⚠️ HISTORY: Entry incompatible with current layout")
            return false
        }
        
        print("🔄 HISTORY RESTORE: Attempting exact restoration of \(entry.debugDescription)")
        
        // PRIORITY 1: Try to restore from serialized DatabasePageContent if available
        if let serializedData = entry.serializedFragmentedPage {
            do {
                let restoredPage = try JSONDecoder().decode(DatabasePageContent.self, from: serializedData)
                currentOptimizedPage = restoredPage
                print("✅ HISTORY RESTORE: Successfully restored from serialized page")
                return true
            } catch {
                print("⚠️ HISTORY RESTORE: Failed to deserialize page: \(error)")
                // Fall through to content recreation
            }
        }
        
        // PRIORITY 2: Recreate page from stored content and metadata
        print("🔄 HISTORY RESTORE: Recreating page from stored content and metadata")
        
        // For legacy pages, try to create a new SliceNode and update currentNode
        let entryKey = VerseKey(book: entry.book, chapter: entry.chapter, verse: entry.verse)
        
        // Check if we can load the chapter to create a proper page
        let entryResult = await loader.loadChapter(book: entry.book, chapter: entry.chapter)
        if case .success = entryResult {
            // Try to generate the page starting from this verse
            let result = await PageContentGenerator.generate(
                from: entryKey,
                pageSize: size,
                using: loader
            )
            
            switch result {
            case .success(let generatedResult):
                let slice = generatedResult.page.toDatabasePageContent()
                currentPage = slice
                currentGeneratedPage = generatedResult.page
                pending = generatedResult.remainder
                
                // Create a new SliceNode for the restored page
                let restoredNode = SliceNode(key: entryKey, slice: slice)
                currentNode = restoredNode
                
                print("✅ HISTORY RESTORE: Successfully recreated page from chapter data")
                return true
                
            case .failure(let error):
                print("❌ HISTORY RESTORE: Failed to regenerate page: \(error)")
                // Fall through to pseudo-page creation
            }
        }
        
        // PRIORITY 3: Create a pseudo-DatabasePageContent using the stored information
        let startVerse = VerseKey(
            book: entry.book,
            chapter: entry.chapter,
            verse: entry.verse
        )
        
        let endVerse = VerseKey(
            book: entry.endBook,
            chapter: entry.endChapter,
            verse: entry.endVerse
        )
        
        // Create verse keys array for the range
        var verseKeys: [VerseKey] = []
        if startVerse.book == endVerse.book && startVerse.chapter == endVerse.chapter {
            for verse in startVerse.verse...endVerse.verse {
                verseKeys.append(VerseKey(book: startVerse.book, chapter: startVerse.chapter, verse: verse))
            }
        } else {
            // For cross-chapter ranges, just include start and end
            verseKeys = [startVerse, endVerse]
        }
        
        let navigationContext = DatabaseNavigationContext(
            chapterNumber: startVerse.chapter,
            verseNumber: startVerse.verse,
            totalChapters: 50, // Would need actual book metadata
            totalVerses: 31   // Would need actual chapter metadata
        )
        
        // Create database verses from verse keys (simplified)
        let databaseVerses: [DatabaseVerse] = verseKeys.map { verseKey in
            DatabaseVerse(
                book: verseKey.book,
                chapter: verseKey.chapter,
                verseNumber: verseKey.verse,
                text: "" // Would need actual verse text
            )
        }

        let restoredPage = DatabasePageContent(
            content: AttributedString(entry.renderedContent),
            verses: databaseVerses,
            verseKeys: verseKeys,
            startVerse: startVerse,
            endVerse: endVerse,
            navigationContext: navigationContext,
            startReference: startVerse.description,
            endReference: endVerse.description,
            references: verseKeys.map { $0.description }
        )
        
        currentOptimizedPage = restoredPage
        print("✅ HISTORY RESTORE: Successfully recreated pseudo-page from metadata")
        return true
    }
}

