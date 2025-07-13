import Foundation

/// Represents a snapshot of a page's fragment range for backward navigation
struct PageSnapshot: Codable, Equatable {
    /// The starting index in the fragment list for this page
    let startFragmentIndex: Int
    
    /// The ending index in the fragment list for this page
    let endFragmentIndex: Int
    
    /// The verse reference where this page begins
    let startVerse: VerseReference
    
    /// The verse reference where this page ends
    let endVerse: VerseReference
    
    /// Navigation title for this page
    let navTitle: String
    
    /// Total number of fragments on this page
    var fragmentCount: Int {
        return endFragmentIndex - startFragmentIndex + 1
    }
    
    /// Debug description for troubleshooting
    var debugDescription: String {
        return "PageSnapshot(fragments: \(startFragmentIndex)-\(endFragmentIndex), verses: \(startVerse.description) to \(endVerse.description), title: \(navTitle))"
    }
}

/// Manages the history of page snapshots for backward navigation
class PageHistoryManager {
    private var snapshots: [PageSnapshot] = []
    private var currentIndex: Int = -1
    
    /// Current page snapshot if available
    var currentSnapshot: PageSnapshot? {
        guard currentIndex >= 0 && currentIndex < snapshots.count else { return nil }
        return snapshots[currentIndex]
    }
    
    /// Whether backward navigation is possible
    var canGoBackward: Bool {
        return currentIndex > 0
    }
    
    /// Whether forward navigation is possible (within history)
    var canGoForward: Bool {
        return currentIndex >= 0 && currentIndex < snapshots.count - 1
    }
    
    /// Add a new page snapshot (for forward navigation)
    func pushSnapshot(_ snapshot: PageSnapshot) {
        // Remove any forward history if we're not at the end
        if currentIndex >= 0 && currentIndex < snapshots.count - 1 {
            snapshots.removeSubrange((currentIndex + 1)...)
        }
        
        // Add new snapshot
        snapshots.append(snapshot)
        currentIndex = snapshots.count - 1
        
        print("📚 HISTORY: Added snapshot \(currentIndex + 1), total: \(snapshots.count)")
        print("📚 SNAPSHOT: \(snapshot.debugDescription)")
    }
    
    /// Move to previous page in history
    func goBackward() -> PageSnapshot? {
        guard canGoBackward else { return nil }
        
        currentIndex -= 1
        let snapshot = snapshots[currentIndex]
        
        print("📚 HISTORY: Moved back to snapshot \(currentIndex + 1)/\(snapshots.count)")
        print("📚 SNAPSHOT: \(snapshot.debugDescription)")
        
        return snapshot
    }
    
    /// Move to next page in history
    func goForward() -> PageSnapshot? {
        guard canGoForward else { return nil }
        
        currentIndex += 1
        let snapshot = snapshots[currentIndex]
        
        print("📚 HISTORY: Moved forward to snapshot \(currentIndex + 1)/\(snapshots.count)")
        print("📚 SNAPSHOT: \(snapshot.debugDescription)")
        
        return snapshot
    }
    
    /// Clear all history
    func clearHistory() {
        snapshots.removeAll()
        currentIndex = -1
        print("📚 HISTORY: Cleared all snapshots")
    }
    
    /// Get debug info about current history state
    func debugInfo() -> String {
        return "History: \(snapshots.count) snapshots, current: \(currentIndex + 1)"
    }
}
