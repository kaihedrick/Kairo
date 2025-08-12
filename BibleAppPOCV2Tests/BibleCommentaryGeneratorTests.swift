// filepath: BibleAppPOCV2Tests/BibleCommentaryGeneratorTests.swift
import XCTest
@testable import BibleAppPOCV2

class BibleCommentaryGeneratorTests: XCTestCase {
    var generator: BibleCommentaryGenerator!
    
    override func setUp() {
        super.setUp()
        generator = BibleCommentaryGenerator.shared
    }
    
    override func tearDown() {
        generator = nil
        super.tearDown()
    }
    
    func testModelLoading() {
        XCTAssertNotNil(generator, "Generator should be initialized")
    }
    
    func testInputFormatting() {
        let formatted = TokenizerService.shared.formatInput(
            verseRef: "Genesis 1:1",
            verseText: "In the beginning God created the heaven and the earth."
        )
        
        XCTAssertTrue(formatted.contains("[VERSE_ID] GENESIS_1_1"))
        XCTAssertTrue(formatted.contains("[VERSE_REF] Genesis 1:1"))
        XCTAssertTrue(formatted.contains("[START_COMMENTARY]"))
    }
    
    func testTokenization() {
        let text = "Hello world"
        let tokens = TokenizerService.shared.tokenize(text)
        
        XCTAssertFalse(tokens.isEmpty, "Tokenization should produce tokens")
        XCTAssertTrue(tokens.allSatisfy { $0 >= 0 && $0 < 50266 }, "Tokens should be within valid range")
    }
    
    func testDetokenization() {
        let originalText = "Hello world"
        let tokens = TokenizerService.shared.tokenize(originalText)
        let detokenized = TokenizerService.shared.detokenize(tokens)
        
        XCTAssertFalse(detokenized.isEmpty, "Detokenization should produce text")
    }
    
    func testFullGenerationPipeline() async {
        let expectation = XCTestExpectation(description: "Generation completed")
        
        await generator.generateCommentary(
            verseRef: "Genesis 1:1",
            verseText: "In the beginning God created the heaven and the earth."
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            XCTAssertFalse(self.generator.generatedText.isEmpty)
            XCTAssertTrue(self.generator.generatedText.contains("[START_COMMENTARY]"))
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 10)
    }
}
