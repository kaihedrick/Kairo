// filepath: BibleAppPOCV2Tests/ModelValidationTests.swift
// filepath: BibleAppPOCV2Tests/ModelValidationTests.swift
import XCTest

@testable import BibleAppPOCV2

final class ModelValidationTests: XCTestCase {
    func testVerseReferenceConstruction() {
        let reference = VerseReference(book: "Genesis", chapter: 1, verse: 1)
        XCTAssertEqual(reference.chapter, 1)
    }

    func testBibleMetadataExists() {
        let meta = BibleMetadata(version: "KJV", language: "EN")
        XCTAssertNotNil(meta)
    }

    func testVerseParsing() {
        let verse = Verse(text: "In the beginning", number: 1)
        XCTAssertEqual(verse.number, 1)
    }
}
