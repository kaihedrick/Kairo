// filepath: BibleAppPOCV2/Services/PageEngine.swift
// PageEngine.swift
// TextKit-based pagination engine for fixed pages with exact verse tapping

import Foundation
import UIKit

/// TextKit-based pagination engine for fixed pages with exact verse tapping
final class PageEngine {
    // Cache: PageKey -> [ReaderPage]
    private var cache: [PageKey: [ReaderPage]] = [:]
    
    /// Paginate a chapter into fixed pages with exact verse mapping
    func paginate(book: String, chapter: Int,
                  runs: [PageSegment], // your verseRuns (attributed + VerseKey)
                  pageSize: CGSize,
                  typography: TypographyMetrics,
                  theme: ThemeMetrics) -> (NSAttributedString, [ReaderPage]) {
        
        let pageKey = PageKey(
            book: book,
            chapter: chapter,
            width: pageSize.width,
            height: pageSize.height,
            fontHash: typography.hashValue,
            themeHash: theme.hashValue
        )
        
        // Check cache first
        if let cached = cache[pageKey] {
            let body = buildBodyAndVerseMap(from: runs).0
            return (body, cached)
        }
        
        // 1) Build body + global verse map
        let (body, globalVerseMap) = buildBodyAndVerseMap(from: runs)
        
        // 2) Create TextKit network
        let storage = NSTextStorage(attributedString: body)
        let layout = NSLayoutManager()           // TK2: NSTextLayoutManager
        storage.addLayoutManager(layout)
        
        // 3) Add containers until all glyphs laid out
        var pages: [ReaderPage] = []
        var glyphIndex = 0
        var pageIndex = 0
        while glyphIndex < layout.numberOfGlyphs {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            
            let glyphRange = layout.glyphRange(for: container)
            let charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            
            // 4) Slice the verse map down to this page
            let pageVerses: [(NSRange, VerseKey)] = globalVerseMap.compactMap { (vr, key) in
                let inter = NSIntersectionRange(vr, charRange)
                return inter.length > 0 ? (inter, key) : nil
            }
            
            pages.append(ReaderPage(index: pageIndex, range: charRange, verseMap: pageVerses))
            glyphIndex = NSMaxRange(glyphRange)
            pageIndex += 1
        }
        
        // Cache the result
        cache[pageKey] = pages
        return (body, pages)
    }
    
    private func buildBodyAndVerseMap(from runs: [PageSegment]) -> (NSAttributedString, [(NSRange, VerseKey)]) {
        let out = NSMutableAttributedString()
        var map: [(NSRange, VerseKey)] = []
        for seg in runs {
            let nsSeg = NSAttributedString(seg.attributed)
            let start = out.length
            out.append(nsSeg)
            if !String(seg.attributed.characters).hasSuffix(" ") { 
                out.append(NSAttributedString(string: " ")) 
            }
            let end = out.length
            map.append((NSRange(location: start, length: end - start), seg.verseKey))
        }
        return (out, map)
    }
    
    /// Clear cache when typography or theme changes
    func invalidateCache() {
        cache.removeAll()
    }
}

/// Typography metrics for cache key
struct TypographyMetrics: Hashable {
    let pointSize: CGFloat
    let fontFamily: String
    let fontWeight: String
    
    var hashValue: Int {
        var hasher = Hasher()
        hasher.combine(pointSize)
        hasher.combine(fontFamily)
        hasher.combine(fontWeight)
        return hasher.finalize()
    }
}

/// Theme metrics for cache key
struct ThemeMetrics: Hashable {
    let isDark: Bool
    let foregroundColor: String
    let backgroundColor: String
    
    var hashValue: Int {
        var hasher = Hasher()
        hasher.combine(isDark)
        hasher.combine(foregroundColor)
        hasher.combine(backgroundColor)
        return hasher.finalize()
    }
}
