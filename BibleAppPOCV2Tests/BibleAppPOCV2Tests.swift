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

}
