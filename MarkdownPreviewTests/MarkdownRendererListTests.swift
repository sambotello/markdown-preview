// MarkdownPreviewTests/MarkdownRendererListTests.swift
import XCTest
@testable import MarkdownPreview

final class MarkdownRendererListTests: XCTestCase {
    private let baseURL = URL(fileURLWithPath: "/tmp")

    func testUnorderedListWithNestedList() {
        let source = """
        - Item one
        - Item two
          - Nested item
        """
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items, let isOrdered) = blocks[0].kind else {
            return XCTFail("Expected list block, got \(blocks[0].kind)")
        }
        XCTAssertFalse(isOrdered)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(String(items[0].content.characters), "Item one")
        XCTAssertEqual(String(items[1].content.characters), "Item two")
        XCTAssertEqual(items[1].children.count, 1)

        guard case .list(let nestedItems, _) = items[1].children[0].kind else {
            return XCTFail("Expected nested list block, got \(items[1].children[0].kind)")
        }
        XCTAssertEqual(String(nestedItems[0].content.characters), "Nested item")
    }

    func testOrderedList() {
        let source = "1. First\n2. Second"
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        guard case .list(let items, let isOrdered) = blocks[0].kind else {
            return XCTFail("Expected list block, got \(blocks[0].kind)")
        }
        XCTAssertTrue(isOrdered)
        XCTAssertEqual(items.map { String($0.content.characters) }, ["First", "Second"])
    }
}
