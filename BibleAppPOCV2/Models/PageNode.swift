// filepath: BibleAppPOCV2/Models/PageNode.swift
//
//  PageNode.swift
//  BibleAppPOCV2
//
//  Created by refactoring from OnDemandPageGenerator.swift
//  Represents a node in the doubly linked list for page navigation
//

import Foundation

/// Node in a doubly linked list for efficient page navigation
final class PageNode {
    let key: VerseKey
    let slice: OptimizedPageSlice
    weak var prev: PageNode?
    weak var next: PageNode?
    
    init(key: VerseKey, slice: OptimizedPageSlice) {
        self.key = key
        self.slice = slice
    }
    
    /// ACID-Safe: Atomically attach this node to the next position
    /// Ensures both directions are linked consistently in a single operation
    func attachNext(_ node: PageNode) {
        self.next = node
        node.prev = self
    }
    
    /// ACID-Safe: Atomically attach this node to the previous position
    /// Ensures both directions are linked consistently in a single operation
    func attachPrevious(_ node: PageNode) {
        self.prev = node
        node.next = self
    }
    
    /// Legacy method for backward compatibility
    func linkNext(_ node: PageNode) {
        attachNext(node)
    }
    
    /// Legacy method for backward compatibility
    func linkPrev(_ node: PageNode) {
        attachPrevious(node)
    }
    
    /// Insert this node after the specified node
    func insertAfter(_ node: PageNode) {
        // Store the old next node
        let oldNext = node.next
        
        // Link this node to the specified node
        node.linkNext(self)
        
        // If there was a next node, link it to this node
        if let oldNext = oldNext {
            self.linkNext(oldNext)
        }
    }
    
    /// Remove this node from the linked list
    func unlink() {
        prev?.next = next
        next?.prev = prev
        prev = nil
        next = nil
    }
    
    /// Trim the linked list to only keep nodes within the specified distance
    func trimToDistance(_ distance: Int) {
        // Trim nodes that are too far in the previous direction
        var current = self
        for _ in 0..<distance {
            guard let prev = current.prev else { break }
            current = prev
        }
        if let prevToRemove = current.prev {
            current.prev = nil
            prevToRemove.next = nil
        }
        
        // Trim nodes that are too far in the next direction
        current = self
        for _ in 0..<distance {
            guard let next = current.next else { break }
            current = next
        }
        if let nextToRemove = current.next {
            current.next = nil
            nextToRemove.prev = nil
        }
    }
    
    /// Debug description showing the linked list structure
    var debugDescription: String {
        let prevKey = prev?.key.description ?? "nil"
        let nextKey = next?.key.description ?? "nil"
        return "PageNode[\(key.description)] prev: \(prevKey), next: \(nextKey)"
    }
}
