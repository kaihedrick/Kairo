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
    @Published private(set) var currentFragmentedPage: FragmentedPage?
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?

    private let cache = PageCache()
    private let loader = OptimizedBibleDataLoader.shared
    private var size: CGSize
    private var currentNode: PageNode?
    private var pending: (key: VerseKey, text: AttributedString)?
    private var fragmentPending: VerseFragment?
    
    // REMOVED: conservativeMultiplier - legacy prediction-based approach
    // WHY: Dynamic height measurement eliminates need for conservative estimation

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
        
        guard size.width > 0 && size.height > 0 else {
            return .failure(.layoutFailed(key))
        }
        
        print("📖 DYNAMIC HEIGHT: Starting page at \(key.description) with size \(size)")
        
        let startVerseIndex = chapter.verses.firstIndex { $0.verse == key.verse } ?? 0
        
        // PRECISION-FIRST PAGINATION: Use exact SwiftUI Text rendering measurements
        // WHY: Eliminates the overflow feedback loop and ensures headers show exactly visible verses
        
        // Calculate available height with extra conservative margin to prevent any overflow
        let conservativeMargin: CGFloat = 20 // Extra safety margin for SwiftUI rendering variations
        let availableHeight = size.height - (LayoutMetrics.verticalPagePadding * 2) - conservativeMargin
        let maxSize = CGSize(width: size.width - (LayoutMetrics.horizontalPagePadding * 2), height: availableHeight)
        
        print("📏 PRECISE LAYOUT: available=\(availableHeight), maxWidth=\(maxSize.width)")
        
        var segments: [PageSegment] = []
        var accumulatedHeight: CGFloat = 0
        var lastCompleteVerseIndex = startVerseIndex - 1
        
        // Add carryover segment if there was one
        if let carryover = tail, !carryover.characters.isEmpty {
            let carryoverHeight = JITTextFormatter.measureText(carryover, maxSize: maxSize).height
            // Extra conservative check - use 95% of available height to be safe
            if accumulatedHeight + carryoverHeight <= availableHeight * 0.95 {
                segments.append(PageSegment(attributed: carryover, verseKey: key, isSplit: true))
                accumulatedHeight += carryoverHeight
                print("📏 Added carryover: height=\(carryoverHeight), total=\(accumulatedHeight)")
            } else {
                print("🚫 Carryover too tall, skipping: \(carryoverHeight) > \(availableHeight * 0.95)")
            }
        }
        
        // Accumulate verses with CONSERVATIVE height checking to prevent any overflow
        for i in startVerseIndex..<chapter.verses.count {
            let verse = chapter.verses[i]
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse)
            
            let formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verse,
                text: verse.text,
                showChapterHeader: verse.verse == 1 && segments.isEmpty,
                showBookTitle: key.chapter == 1 && verse.verse == 1 && segments.isEmpty
            )
            
            // Measure this verse's actual height
            let verseHeight = JITTextFormatter.measureText(formatted, maxSize: maxSize).height
            
            // CONSERVATIVE CHECK: Use 95% of available height to prevent any overflow
            let heightLimit = availableHeight * 0.95
            if accumulatedHeight + verseHeight <= heightLimit {
                segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
                accumulatedHeight += verseHeight
                lastCompleteVerseIndex = i
                print("📏 Added verse \(verse.verse): height=\(verseHeight), total=\(accumulatedHeight)/\(heightLimit)")
            } else {
                print("🛑 CONSERVATIVE STOP: Verse \(verse.verse) would exceed 95% limit")
                print("    Height needed: \(verseHeight), Available: \(heightLimit - accumulatedHeight)")
                break
            }
        }
        
        // Emergency fallback - ensure we have at least one verse
        if segments.isEmpty {
            let verse = chapter.verses[startVerseIndex]
            let verseKey = VerseKey(book: key.book, chapter: key.chapter, verse: verse.verse)
            
            let formatted = JITTextFormatter.formatVerse(
                book: key.book,
                chapter: key.chapter,
                verse: verse.verse,
                text: verse.text,
                showChapterHeader: verse.verse == 1,
                showBookTitle: key.chapter == 1 && verse.verse == 1
            )
            
            segments.append(PageSegment(attributed: formatted, verseKey: verseKey))
            lastCompleteVerseIndex = startVerseIndex
            print("🚨 Emergency fallback: added verse \(verse.verse) (page must have at least one verse)")
        }
        
        // Handle remainder - continue from the next verse that didn't fit
        let remainder: (key: VerseKey, text: AttributedString)? = {
            let nextVerseIndex = lastCompleteVerseIndex + 1
            if nextVerseIndex < chapter.verses.count {
                let nextVerse = chapter.verses[nextVerseIndex]
                return (key: VerseKey(book: key.book, chapter: key.chapter, verse: nextVerse.verse), text: AttributedString())
            } else {
                return nil // No more verses in this chapter
            }
        }()
        
        let startVerse = chapter.verses[startVerseIndex]
        let endVerse = chapter.verses[lastCompleteVerseIndex]
        
        let page = GeneratedPage(
            segments: segments,
            startKey: VerseKey(book: key.book, chapter: key.chapter, verse: startVerse.verse),
            navigationContext: .init(isFirstVerseOfBook: false, isLastVerseOfBook: false)
        )
        
        print("📄 PRECISION RESULT: verses \(startVerse.verse)-\(endVerse.verse) (\(segments.count) verses)")
        print("📄 Conservative height used: \(accumulatedHeight) of \(availableHeight * 0.95) limit")
        print("📄 Actual available space: \(availableHeight) (with \(conservativeMargin)pt safety margin)")
        print("📄 Has remainder: \(remainder != nil)")
        
        return .success((page: page, remainder: remainder))
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
    
    /// Generate a page using the new fragment-based approach
    func generateFragmentedPage(startingAt verse: (book: String, chapter: Int, verse: Int)) async {
        let key = VerseKey(book: verse.book, chapter: verse.chapter, verse: verse.verse)
        lastError = nil
        
        // Prevent duplicate generation if we're already generating this key
        if isGenerating {
            print("⚠️ Already generating fragmented page, skipping duplicate request for \(key.description)")
            return
        }
        
        // Check if we already have this page loaded
        if let current = currentFragmentedPage, current.startVerse.book == key.book && 
           current.startVerse.chapter == key.chapter && current.startVerse.verse == key.verse {
            print("✅ Fragmented page \(key.description) already loaded, skipping generation")
            return
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        do {
            let fragmentedPage = try await generateFragmentedPageContent(startingAt: key)
            currentFragmentedPage = fragmentedPage
            
            // Also update the legacy currentPage for backward compatibility
            currentPage = OptimizedPageSlice(
                content: fragmentedPage.content,
                verseKeys: fragmentedPage.verseKeys,
                startVerse: VerseKey(
                    book: fragmentedPage.startVerse.book,
                    chapter: fragmentedPage.startVerse.chapter,
                    verse: fragmentedPage.startVerse.verse
                ),
                endVerse: VerseKey(
                    book: fragmentedPage.endVerse.book,
                    chapter: fragmentedPage.endVerse.chapter,
                    verse: fragmentedPage.endVerse.verse
                ),
                navigationContext: PageNavigationContext(
                    isFirstVerseOfBook: fragmentedPage.startVerse.book == "Genesis" && fragmentedPage.startVerse.chapter == 1 && fragmentedPage.startVerse.verse == 1,
                    isLastVerseOfBook: false // We'll set this properly later when we know the book structure
                )
            )
            
            print("📖 FRAGMENTED PAGE GENERATED: \(fragmentedPage.debugDescription)")
            
        } catch {
            lastError = error.localizedDescription
            print("❌ Failed to generate fragmented page: \(error.localizedDescription)")
        }
    }
    
    /// Generate fragmented page content with cross-page verse continuation
    private func generateFragmentedPageContent(startingAt key: VerseKey) async throws -> FragmentedPage {
        guard let chapter = await loader.loadChapterContent(book: key.book, chapter: key.chapter) else {
            throw PageGenerationError.missingChapter(key)
        }
        
        guard size.width > 0 && size.height > 0 else {
            throw PageGenerationError.layoutFailed(key)
        }
        
        print("📖 FRAGMENT GENERATION: Starting at \(key.description) with size \(size)")
        
        // Calculate available space for fragments
        let conservativeMargin: CGFloat = 30 // Extra margin for fragment indicators
        let availableHeight = size.height - (LayoutMetrics.verticalPagePadding * 2) - conservativeMargin
        let maxSize = CGSize(width: size.width - (LayoutMetrics.horizontalPagePadding * 2), height: availableHeight)
        
        print("📏 FRAGMENT LAYOUT: available=\(availableHeight), maxWidth=\(maxSize.width)")
        
        var fragments: [VerseFragment] = []
        var accumulatedHeight: CGFloat = 0
        var currentVerseIndex = chapter.verses.firstIndex { $0.verse == key.verse } ?? 0
        
        // Handle pending fragment from previous page
        if let pendingFragment = fragmentPending {
            let fragmentHeight = measureFragmentHeight(pendingFragment, maxSize: maxSize)
            if accumulatedHeight + fragmentHeight <= availableHeight * 0.95 {
                fragments.append(pendingFragment)
                accumulatedHeight += fragmentHeight
                print("📏 Added pending fragment: height=\(fragmentHeight), total=\(accumulatedHeight)")
            }
            fragmentPending = nil
        }
        
        // Process verses starting from the current position
        while currentVerseIndex < chapter.verses.count {
            let verse = chapter.verses[currentVerseIndex]
            let verseRef = VerseReference(
                unsafeBook: key.book,
                unsafeChapter: key.chapter,
                unsafeVerse: verse.verse
            )
            let domainVerse = Verse(reference: verseRef, text: verse.text)
            
            // Generate fragments for this verse
            let remainingHeight = availableHeight * 0.95 - accumulatedHeight
            let verseFragments = VerseFragmentGenerator.fragmentVerse(
                verse: domainVerse,
                availableHeight: remainingHeight,
                maxSize: maxSize
            )
            
            var addedFragments = 0
            for fragment in verseFragments {
                let fragmentHeight = measureFragmentHeight(fragment, maxSize: maxSize)
                
                if accumulatedHeight + fragmentHeight <= availableHeight * 0.95 {
                    fragments.append(fragment)
                    accumulatedHeight += fragmentHeight
                    addedFragments += 1
                    print("📏 Added fragment \(fragment.sequenceNumber + 1)/\(fragment.totalFragments): height=\(fragmentHeight), total=\(accumulatedHeight)")
                } else {
                    // This fragment doesn't fit, save it for next page
                    fragmentPending = fragment
                    print("🔄 Fragment \(fragment.sequenceNumber + 1)/\(fragment.totalFragments) saved for next page")
                    break
                }
            }
            
            // If we added all fragments for this verse, move to next verse
            if addedFragments == verseFragments.count {
                currentVerseIndex += 1
            } else {
                // We have a pending fragment, stop here
                break
            }
            
            // Safety check to prevent infinite loops
            if fragments.count > 50 {
                print("⚠️ Safety break: too many fragments on one page")
                break
            }
        }
        
        // Ensure we have at least one fragment
        if fragments.isEmpty {
            print("🚨 Emergency: No fragments fit, adding first verse as single fragment")
            let verse = chapter.verses[currentVerseIndex]
            let verseRef = VerseReference(
                unsafeBook: key.book,
                unsafeChapter: key.chapter,
                unsafeVerse: verse.verse
            )
            
            let emergencyFragment = VerseFragment(
                reference: verseRef,
                textFragment: verse.text,
                isStartOfVerse: true,
                isEndOfVerse: true,
                fullVerseText: verse.text,
                sequenceNumber: 0,
                totalFragments: 1
            )
            fragments.append(emergencyFragment)
        }
        
        // Generate the combined content
        let combinedContent = VerseFragmentGenerator.combineFragments(fragments)
        
        // Create navigation title
        let startVerse = fragments.first!.reference
        let endVerse = fragments.last!.reference
        let navTitle = if startVerse.book == endVerse.book && startVerse.chapter == endVerse.chapter {
            if startVerse.verse == endVerse.verse {
                "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse)"
            } else {
                "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse)-\(endVerse.verse)"
            }
        } else if startVerse.book == endVerse.book {
            "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse) - \(endVerse.chapter):\(endVerse.verse)"
        } else {
            "\(startVerse.book) \(startVerse.chapter):\(startVerse.verse) - \(endVerse.book) \(endVerse.chapter):\(endVerse.verse)"
        }
        
        return FragmentedPage(
            fragments: fragments,
            navTitle: navTitle,
            startVerse: startVerse,
            endVerse: endVerse,
            content: combinedContent,
            measuredHeight: accumulatedHeight,
            availableHeight: availableHeight
        )
    }
    
    /// Measure the height of a fragment for layout calculations
    private func measureFragmentHeight(_ fragment: VerseFragment, maxSize: CGSize) -> CGFloat {
        let formatted = JITTextFormatter.formatVerse(
            book: fragment.reference.book,
            chapter: fragment.reference.chapter,
            verse: fragment.reference.verse,
            text: fragment.displayText
        )
        
        return JITTextFormatter.measureText(formatted, maxSize: maxSize).height
    }
    
    /// Navigate to next page with fragment support
    func generateNextFragmentedPage() async {
        defer { Task { await trimCacheToThreePages() } }
        
        // If we have a pending fragment, generate page starting with it
        if let pendingFragment = fragmentPending {
            await generateFragmentedPage(startingAt: (
                pendingFragment.reference.book,
                pendingFragment.reference.chapter,
                pendingFragment.reference.verse
            ))
            return
        }
        
        // Find the next verse after the current page's end
        guard let current = currentFragmentedPage,
              let nextVerse = await findNextVerse(after: VerseKey(
                book: current.endVerse.book,
                chapter: current.endVerse.chapter,
                verse: current.endVerse.verse
              )) else { return }
        
        await generateFragmentedPage(startingAt: (nextVerse.book, nextVerse.chapter, nextVerse.verse))
    }
    
    /// Navigate to previous page with fragment support
    func generatePreviousFragmentedPage() async {
        defer { Task { await trimCacheToThreePages() } }
        
        guard let current = currentFragmentedPage,
              let prevVerse = await findPreviousVerse(before: VerseKey(
                book: current.startVerse.book,
                chapter: current.startVerse.chapter,
                verse: current.startVerse.verse
              )) else { return }
        
        // Clear any pending fragment when going backwards
        fragmentPending = nil
        
        await generateFragmentedPage(startingAt: (prevVerse.book, prevVerse.chapter, prevVerse.verse))
    }
}

