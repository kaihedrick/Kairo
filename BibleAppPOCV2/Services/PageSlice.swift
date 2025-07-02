// PageSlice.swift
// Defines one "page" of text with its identifying verse-keys

import Foundation
import SwiftUI   // Needed for AttributedString

struct PageSlice: Identifiable {
    let id = UUID()
    let content: AttributedString
    let verseKeys: [String]   // e.g. ["Matthew:1:1", "Matthew:1:2"]
}
