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
    private let historyManager = PageHistoryService()
    private var size: CGSize
    private var currentNode: PageNode?
    private var pending: (key: VerseKey, text: AttributedString)?
    private var fragmentPending: VerseFragment?
    private var isNavigatingFromHistory = false

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
        currentFragmentedPage = nil
        
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
            print("📖 LINKED LIST: Reused current node for \(key.description)")
            return
        } else if let node = currentNode?.next, node.key == key {
            currentNode = node
            currentPage = node.slice
            print("📖 LINKED LIST: Moved to next node for \(key.description)")
            return
        } else if let node = currentNode?.prev, node.key == key {
            currentNode = node
            currentPage = node.slice
            print("📖 LINKED LIST: Moved to prev node for \(key.description)")
            return
        }

        if pending == nil, let cached = await cache.get(key) {
            let newNode = PageNode(key: key, slice: cached)
            
            // Properly link the new node into the doubly linked list
            if isNavigatingFromHistory {
                // When navigating from history, we need to be careful not to break the chain
                // Store the old current node to reconnect later
                if let oldNode = currentNode {
                    newNode.prev = oldNode
                    oldNode.next = newNode
                }
                print("📖 LINKED LIST: Created new node from cache during history navigation")
            } else {
                // Normal forward navigation
                if let oldNode = currentNode {
                    newNode.prev = oldNode
                    oldNode.next = newNode
                }
                print("📖 LINKED LIST: Created new node from cache during normal navigation")
            }
            
            currentNode = newNode
            await commitCurrentPage(cached, key: key)
            trimLinkedList()
            currentPage = cached
            
            // Debug log the linked list state
            print("📖 LINKED LIST: Loaded \(key.description), Prev: \(currentNode?.prev?.key.description ?? "nil"), Next: \(currentNode?.next?.key.description ?? "nil")")
            return
        }

        let tail = (pending?.key == key) ? pending?.text : nil
        pending = nil
        let result = await PageContentGenerator.generate(
            from: key,
            pageSize: size,
            tail: tail,
            using: loader
        )
        
        switch result {
        case .success(let generatedResult):
            let slice = generatedResult.page.toOptimizedPageSlice()
            currentPage = slice
            pending = generatedResult.remainder
            let newNode = PageNode(key: key, slice: slice)
            
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
                historyManager.pushPage(slice: slice, pageSize: size)
            }
            
            // Debug log the linked list state
            print("📖 LINKED LIST: Generated \(key.description), Prev: \(currentNode?.prev?.key.description ?? "nil"), Next: \(currentNode?.next?.key.description ?? "nil")")
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
        
        // Check if we have a cached previous page in the linked list
        if let node = currentNode?.prev {
            currentNode = node
            currentPage = node.slice
            pending = nil
            print("📖 LINKED LIST: Used cached previous page for \(node.key.description)")
            return
        }
        
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
        Current fragmented page: \(currentFragmentedPage?.debugDescription ?? "none")
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
        // Skip trimming during history navigation to preserve valid PageNodes
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
        if let p2 = cur.prev?.prev { p2.next = nil; p2.prev = nil }
        if let n2 = cur.next?.next { n2.prev = nil; n2.next = nil }
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
            let result = try await FragmentedPageGenerator.generateContent(
                startingAt: key,
                pageSize: size,
                fragmentPending: fragmentPending,
                using: loader
            )
            
            currentFragmentedPage = result.page
            fragmentPending = result.pendingFragment
            
            // Create and store history entry for reliable backward navigation
            if !isNavigatingFromHistory {
                historyManager.pushFragmentedPage(result.page, pageSize: size)
                print("📚 HISTORY TRACKING: Added new page to history (\(historyManager.historyCount) total)")
            } else {
                print("📚 HISTORY TRACKING: Skipped adding page (navigating from history)")
            }
            
            print("📖 FRAGMENTED PAGE GENERATED: \(result.page.debugDescription)")
            
        } catch {
            lastError = error.localizedDescription
            print("❌ Failed to generate fragmented page: \(error.localizedDescription)")
        }
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
    
    /// Navigate to previous page with enhanced history - NO UNRELIABLE FALLBACK
    func generatePreviousFragmentedPage() async {
        defer { Task { await trimCacheToThreePages() } }
        
        // Store the current fragmented page for potential reconnection
        let oldFragmentedPage = currentFragmentedPage
        
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
                if let restoredPage = currentFragmentedPage,
                   let oldPage = oldFragmentedPage {
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
    func generateNextFragmentedPageWithHistory() async {
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
        await generateNextFragmentedPage()
    }
    
    /// Navigate to the next page of verses using the fragment-based approach
    func goToNextPage() async {
        print("📚 PAGE NAVIGATION: Going to next page")
        await generateNextFragmentedPageWithHistory()
    }
    
    /// Navigate back to the previous full page of verses using history snapshots
    func goToPreviousPage() async {
        print("📚 PAGE NAVIGATION: Going to previous page")
        await generatePreviousFragmentedPage()
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
        
        // PRIORITY 1: Try to restore from serialized FragmentedPage if available
        if let serializedData = entry.serializedFragmentedPage {
            do {
                let restoredPage = try JSONDecoder().decode(FragmentedPage.self, from: serializedData)
                currentFragmentedPage = restoredPage
                print("✅ HISTORY RESTORE: Successfully restored from serialized page")
                return true
            } catch {
                print("⚠️ HISTORY RESTORE: Failed to deserialize page: \(error)")
                // Fall through to content recreation
            }
        }
        
        // PRIORITY 2: Recreate page from stored content and metadata
        print("🔄 HISTORY RESTORE: Recreating page from stored content and metadata")
        
        // For legacy pages, try to create a new PageNode and update currentNode
        let entryKey = VerseKey(book: entry.book, chapter: entry.chapter, verse: entry.verse)
        
        // Check if we can load the chapter to create a proper page
        if let chapter = await loader.loadChapterContent(book: entry.book, chapter: entry.chapter) {
            // Try to generate the page starting from this verse
            let result = await PageContentGenerator.generate(
                from: entryKey,
                pageSize: size,
                using: loader
            )
            
            switch result {
            case .success(let generatedResult):
                let slice = generatedResult.page.toOptimizedPageSlice()
                currentPage = slice
                pending = generatedResult.remainder
                
                // Create a new PageNode for the restored page
                let restoredNode = PageNode(key: entryKey, slice: slice)
                currentNode = restoredNode
                
                print("✅ HISTORY RESTORE: Successfully recreated page from chapter data")
                return true
                
            case .failure(let error):
                print("❌ HISTORY RESTORE: Failed to regenerate page: \(error)")
                // Fall through to pseudo-page creation
            }
        }
        
        // PRIORITY 3: Create a pseudo-FragmentedPage using the stored information
        let startVerseRef = VerseReference(
            unsafeBook: entry.book,
            unsafeChapter: entry.chapter,
            unsafeVerse: entry.verse
        )
        
        let endVerseRef = VerseReference(
            unsafeBook: entry.endBook,
            unsafeChapter: entry.endChapter,
            unsafeVerse: entry.endVerse
        )
        
        // For exact restoration, we need to create fragment(s) that match the original content
        let mainFragment = VerseFragment(
            reference: startVerseRef,
            textFragment: entry.renderedContent,
            isStartOfVerse: entry.characterOffset == nil,
            isEndOfVerse: !entry.hasSplitVerses,
            fullVerseText: entry.renderedContent,
            sequenceNumber: entry.fragmentOffset ?? 0,
            totalFragments: entry.hasSplitVerses ? 2 : 1 // Conservative estimate
        )
        
        let restoredPage = FragmentedPage(
            fragments: [mainFragment],
            navTitle: entry.navTitle,
            startVerse: startVerseRef,
            endVerse: endVerseRef,
            content: AttributedString(entry.renderedContent),
            measuredHeight: size.height * 0.8, // Estimate based on page size
            availableHeight: size.height - (LayoutMetrics.verticalPagePadding * 2)
        )
        
        currentFragmentedPage = restoredPage
        print("✅ HISTORY RESTORE: Successfully recreated pseudo-page from metadata")
        return true
    }
}

