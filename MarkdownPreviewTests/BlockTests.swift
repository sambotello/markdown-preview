// MarkdownPreviewTests/BlockTests.swift
import XCTest
@testable import MarkdownPreview

final class BlockTests: XCTestCase {
    func testEqualParagraphBlocksAreEqual() {
        let a = Block(kind: .paragraph(text: AttributedString("Hello")))
        let b = Block(kind: .paragraph(text: AttributedString("Hello")))
        XCTAssertEqual(a, b)
    }

    func testDifferentKindsAreNotEqual() {
        let heading = Block(kind: .heading(level: 1, text: AttributedString("Title")))
        let paragraph = Block(kind: .paragraph(text: AttributedString("Title")))
        XCTAssertNotEqual(heading, paragraph)
    }
}
