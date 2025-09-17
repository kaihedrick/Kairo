// filepath: BibleAppPOCV2/Models/PageHistoryEntry.swift
import Foundation
import SwiftUI

/// Represents a fragmented page for layout and rendering
struct FragmentedPage: Codable {
    let fragments: [VerseFragment]
    let navTitle: String
    let startVerse: String
    let endVerse: String
    let content: String // Store as string for Codable
    let measuredHeight: CGFloat
    let availableHeight: CGFloat

    init(fragments: [VerseFragment], navTitle: String, startVerse: String, endVerse: String, content: AttributedString, measuredHeight: CGFloat, availableHeight: CGFloat) {
        self.fragments = fragments
        self.navTitle = navTitle
        self.startVerse = startVerse
        self.endVerse = endVerse
        self.content = String(content.characters)
        self.measuredHeight = measuredHeight
        self.availableHeight = availableHeight
    }

    // Legacy constructor for backward compatibility
    init(book: String, chapter: Int, verse: Int, fragments: [String] = [], layoutInfo: [String: Any] = [:]) {
        self.fragments = []
        self.navTitle = "\(book) \(chapter):\(verse)"
        self.startVerse = "\(book) \(chapter):\(verse)"
        self.endVerse = "\(book) \(chapter):\(verse)"
        self.content = fragments.joined(separator: " ")
        self.measuredHeight = 0
        self.availableHeight = 0
    }

    var contentString: String {
        return content
    }

    var debugDescription: String {
        return "FragmentedPage(navTitle: \(navTitle), startVerse: \(startVerse), endVerse: \(endVerse), fragments: \(fragments.count))"
    }
}



/// Represents a verse fragment for pagination
struct VerseFragment: Codable {
    let reference: String
    let textFragment: String
    let isStartOfVerse: Bool
    let isEndOfVerse: Bool
    let fullVerseText: String
    let sequenceNumber: Int
    let totalFragments: Int

    init(reference: String, textFragment: String, isStartOfVerse: Bool, isEndOfVerse: Bool, fullVerseText: String, sequenceNumber: Int, totalFragments: Int) {
        self.reference = reference
        self.textFragment = textFragment
        self.isStartOfVerse = isStartOfVerse
        self.isEndOfVerse = isEndOfVerse
        self.fullVerseText = fullVerseText
        self.sequenceNumber = sequenceNumber
        self.totalFragments = totalFragments
    }

    // Legacy constructor for backward compatibility
    init(book: String, chapter: Int, verse: Int, text: String, attributedText: AttributedString, characterOffset: Int = 0) {
        self.reference = "\(book) \(chapter):\(verse)"
        self.textFragment = text
        self.isStartOfVerse = characterOffset == 0
        self.isEndOfVerse = true
        self.fullVerseText = text
        self.sequenceNumber = characterOffset
        self.totalFragments = 1
    }
}

/// Enhanced page history entry that stores complete layout information for exact page reproduction
struct PageHistoryEntry: Equatable {
    /// The book name where this page starts
    let book: String
    
    /// The chapter number where this page starts
    let chapter: Int
    
    /// The verse number where this page starts
    let verse: Int
    
    /// Character offset within the verse if the page starts mid-verse (for verse splicing)
    let characterOffset: Int?
    
    /// Fragment offset for more precise positioning
    let fragmentOffset: Int?
    
    /// The exact content that was rendered on this page
    let renderedContent: String
    
    /// Navigation title for this page
    let navTitle: String
    
    /// The page size this was rendered for
    let pageSize: CGSize
    
    /// Hash of the layout parameters to ensure compatibility
    let layoutHash: String
    
    /// Timestamp when this page was created
    let timestamp: Date
    
    /// Serialized FragmentedPage for exact restoration (if available)
    let serializedFragmentedPage: Data?
    
    /// List of verse keys that appear on this page for validation
    let verseKeys: [String]
    
    /// Whether this page contains split verses
    let hasSplitVerses: Bool
    
    /// End verse information for better validation
    let endBook: String
    let endChapter: Int
    let endVerse: Int
    
    /// Create a layout hash from current rendering parameters
    static func createLayoutHash(pageSize: CGSize, horizontalPadding: CGFloat, verticalPadding: CGFloat) -> String {
        let hashString = "\(pageSize.width)x\(pageSize.height)_h\(horizontalPadding)_v\(verticalPadding)"
        return hashString.replacingOccurrences(of: ".", with: "_")
    }
    
    /// Check if this history entry is compatible with current layout
    func isCompatibleWith(pageSize: CGSize, horizontalPadding: CGFloat, verticalPadding: CGFloat) -> Bool {
        let currentHash = PageHistoryEntry.createLayoutHash(
            pageSize: pageSize,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
        return layoutHash == currentHash
    }

    /// Create a history entry from DatabasePageContent
    static func createFromDatabasePage(_ page: DatabasePageContent,
                                       pageSize: CGSize,
                                       horizontalPadding: CGFloat,
                                       verticalPadding: CGFloat) -> PageHistoryEntry {
        let layoutHash = createLayoutHash(pageSize: pageSize,
                                          horizontalPadding: horizontalPadding,
                                          verticalPadding: verticalPadding)

        return PageHistoryEntry(
            book: page.startVerse.book,
            chapter: page.startVerse.chapter,
            verse: page.startVerse.verse,
            renderedContent: String(page.content.characters),
            navTitle: page.navTitle,
            pageSize: pageSize,
            layoutHash: layoutHash,
            verseKeys: page.verseKeys.map { "\($0.book) \($0.chapter):\($0.verse)" },
            hasSplitVerses: false, // Database pages don't split verses
            endBook: page.endVerse.book,
            endChapter: page.endVerse.chapter,
            endVerse: page.endVerse.verse
        )
    }
    
    /// Debug description for troubleshooting
    var debugDescription: String {
        let offsetInfo = characterOffset != nil ? " offset:\(characterOffset!)" : ""
        let fragmentInfo = fragmentOffset != nil ? " fragment:\(fragmentOffset!)" : ""
        let splitInfo = hasSplitVerses ? " [SPLIT]" : ""
        return "PageHistoryEntry(\(book) \(chapter):\(verse)\(offsetInfo)\(fragmentInfo) → \(endBook) \(endChapter):\(endVerse)\(splitInfo), size:\(pageSize))"
    }
    
    /// Custom initializer for PageHistoryEntry
    init(
        book: String,
        chapter: Int,
        verse: Int,
        characterOffset: Int? = nil,
        fragmentOffset: Int? = nil,
        renderedContent: String,
        navTitle: String,
        pageSize: CGSize,
        layoutHash: String,
        timestamp: Date = Date(),
        serializedFragmentedPage: Data? = nil,
        verseKeys: [String] = [],
        hasSplitVerses: Bool = false,
        endBook: String? = nil,
        endChapter: Int? = nil,
        endVerse: Int? = nil
    ) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.characterOffset = characterOffset
        self.fragmentOffset = fragmentOffset
        self.renderedContent = renderedContent
        self.navTitle = navTitle
        self.pageSize = pageSize
        self.layoutHash = layoutHash
        self.timestamp = timestamp
        self.serializedFragmentedPage = serializedFragmentedPage
        self.verseKeys = verseKeys
        self.hasSplitVerses = hasSplitVerses
        
        // Default to start verse if end verse not provided
        self.endBook = endBook ?? book
        self.endChapter = endChapter ?? chapter
        self.endVerse = endVerse ?? verse
    }
    
    /// Create a comprehensive history entry from an OptimizedPageSlice
    static func createFromOptimizedPage(
        _ page: OptimizedPageSlice,
        pageSize: CGSize,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        characterOffset: Int? = nil,
        fragmentOffset: Int? = nil
    ) -> PageHistoryEntry {
        let layoutHash = createLayoutHash(
            pageSize: pageSize,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
        
        // Serialize the page for exact restoration
        let serializedPage: Data? = {
            do {
                return try JSONEncoder().encode(page)
            } catch {
                print("⚠️ Failed to serialize OptimizedPageSlice: \(error)")
                return nil
            }
        }()
        
        // Extract verse keys for validation
        let verseKeys = page.verseKeys.map { verseKey in
            "\(verseKey.book) \(verseKey.chapter):\(verseKey.verse)"
        }
        
        // OptimizedPageSlice doesn't track split verses directly, so set to false
        let hasSplitVerses = false
        
        return PageHistoryEntry(
            book: page.startVerse.book,
            chapter: page.startVerse.chapter,
            verse: page.startVerse.verse,
            characterOffset: characterOffset,
            fragmentOffset: fragmentOffset,
            renderedContent: String(page.content.characters), // Convert AttributedString to String
            navTitle: page.navTitle,
            pageSize: pageSize,
            layoutHash: layoutHash,
            serializedFragmentedPage: serializedPage,
            verseKeys: verseKeys,
            hasSplitVerses: hasSplitVerses,
            endBook: page.endVerse.book,
            endChapter: page.endVerse.chapter,
            endVerse: page.endVerse.verse
        )
    }
}

/// Enhanced page history manager with reliable backward navigation
class EnhancedPageHistoryManager: ObservableObject {
    @Published private var history: [PageHistoryEntry] = []
    @Published private var currentIndex: Int = -1
    
    /// Maximum number of pages to keep in history
    private let maxHistorySize = 100
    
    /// Current page entry if available
    var currentEntry: PageHistoryEntry? {
        guard currentIndex >= 0 && currentIndex < history.count else { return nil }
        return history[currentIndex]
    }
    
    /// Whether backward navigation is possible
    var canGoBackward: Bool {
        return currentIndex > 0
    }
    
    /// Whether forward navigation is possible (within history)
    var canGoForward: Bool {
        return currentIndex >= 0 && currentIndex < history.count - 1
    }
    
    /// Total number of pages in history
    var historyCount: Int {
        return history.count
    }
    
    /// Push a new page to history when navigating forward
    func pushPage(_ entry: PageHistoryEntry) {
        // Remove any forward history if we're not at the end
        if currentIndex >= 0 && currentIndex < history.count - 1 {
            history.removeSubrange((currentIndex + 1)...)
        }
        
        // Add new entry
        history.append(entry)
        currentIndex = history.count - 1
        
        // Trim history if it gets too large
        if history.count > maxHistorySize {
            history.removeFirst(history.count - maxHistorySize)
            currentIndex = history.count - 1
        }
        
        print("📚 ENHANCED HISTORY: Added page \(currentIndex + 1), total: \(history.count)")
        print("📚 ENTRY: \(entry.debugDescription)")
    }
    
    /// Push a page back to history (used when restoration fails)
    func pushPageBack(_ entry: PageHistoryEntry) {
        // Insert the entry back at the current position
        if currentIndex >= 0 && currentIndex < history.count {
            history.insert(entry, at: currentIndex + 1)
        } else {
            history.append(entry)
            currentIndex = history.count - 1
        }
        
        print("📚 ENHANCED HISTORY: Pushed page back to history at position \(currentIndex + 1)")
    }
    
    /// Navigate backward in history
    func goBackward() -> PageHistoryEntry? {
        guard canGoBackward else { return nil }
        
        currentIndex -= 1
        let entry = history[currentIndex]
        
        print("📚 ENHANCED HISTORY: Moved back to page \(currentIndex + 1)/\(history.count)")
        print("📚 ENTRY: \(entry.debugDescription)")
        
        return entry
    }
    
    /// Navigate forward in history
    func goForward() -> PageHistoryEntry? {
        guard canGoForward else { return nil }
        
        currentIndex += 1
        let entry = history[currentIndex]
        
        print("📚 ENHANCED HISTORY: Moved forward to page \(currentIndex + 1)/\(history.count)")
        print("📚 ENTRY: \(entry.debugDescription)")
        
        return entry
    }
    
    /// Clear all history (called when page size changes)
    func clearHistory() {
        history.removeAll()
        currentIndex = -1
        print("📚 ENHANCED HISTORY: Cleared all pages")
    }
    
    /// Clean up incompatible entries when layout changes
    func cleanupIncompatibleEntries(pageSize: CGSize, horizontalPadding: CGFloat, verticalPadding: CGFloat) {
        let compatibleEntries = history.filter { entry in
            entry.isCompatibleWith(pageSize: pageSize, horizontalPadding: horizontalPadding, verticalPadding: verticalPadding)
        }
        
        if compatibleEntries.count != history.count {
            print("📚 ENHANCED HISTORY: Cleaned up \(history.count - compatibleEntries.count) incompatible entries")
            history = compatibleEntries
            currentIndex = min(currentIndex, history.count - 1)
        }
    }
    
    /// Get debug info about current history state
    func getDebugInfo() -> String {
        return """
        Enhanced History State:
        - Total pages: \(history.count)
        - Current index: \(currentIndex)
        - Can go backward: \(canGoBackward)
        - Can go forward: \(canGoForward)
        - Current entry: \(currentEntry?.debugDescription ?? "None")
        """
    }
}
