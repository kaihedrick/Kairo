// filepath: BibleAppPOCV2Tests/BibleAppPOCV2Tests.swift
// filepath: BibleAppPOCV2/BibleAppPOCV2Tests/BibleAppPOCV2Tests.swift
//
//  BibleAppPOCV2Tests.swift
//  BibleAppPOCV2Tests
//
//  Created by Jeff Hedrick on 6/13/25.
//

import Testing
@testable import BibleAppPOCV2

struct BibleAppPOCV2Tests {

    /// Verify the first page of Mark 1 ends at verse 17 on iPhone size.
    @Test func testMarkFirstPageEndVerse() async throws {
        let generator = OnDemandPageGenerator(pageSize: CGSize(width: 390, height: 600))
        await generator.generatePage(startingAt: ("Mark", 1, 1))
        let page = generator.currentPage?.toOptimizedPageSlice()
        #expect(page?.endVerse.verse == 17)
    }

    /// Verify the paginator links pages without skipping verses.
    @Test func testNextPageStartVerse() async throws {
        let generator = OnDemandPageGenerator(pageSize: CGSize(width: 390, height: 600))
        await generator.generatePage(startingAt: ("Mark", 1, 1))
        let first = generator.currentPage!
        await generator.generateNextPage()
        let second = generator.currentPage!
        let diff = second.startVerse.verse - first.endVerse.verse
        #expect(diff == 0 || diff == 1)
    }

}
