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

    // Verified empirically (see task-14-report.md) that a `SoftBreak`/`LineBreak` node
    // formatted in isolation via `.format()` produces "" instead of its real separator,
    // because `.format()` derives that separator from a continuous formatting pass over
    // a run of siblings — a fix already applied to `inlineText(_:)` for headings/
    // paragraphs/table cells. List items reuse the same helper (with dedent enabled), so
    // a plain word-wrapped bullet must join its two source lines with a space, not
    // concatenate them.
    func testListItemWithSoftWrapJoinsLinesWithSpace() {
        let source = """
        - This is a long line
          that wraps to two source lines
        """
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        guard case .list(let items, _) = blocks[0].kind else {
            return XCTFail("Expected list block, got \(blocks[0].kind)")
        }
        XCTAssertEqual(
            String(items[0].content.characters),
            "This is a long line that wraps to two source lines"
        )
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

    // Verified empirically (see task-5-report.md) that a hard line break which is a
    // *direct* child of a list item's paragraph never produces a literal "\n" in the
    // joined `.format()` source: each paragraph child is formatted independently via
    // `markup.children.map { $0.format() }`, so the newline `LineBreak.format()` queues
    // is never flushed (nothing else is printed within that isolated formatting call) —
    // it collapses into extra leaked alignment-prefix spaces instead of an embedded "\n".
    //
    // A literal "\n" *does* appear when the line break is nested inside another inline
    // span (e.g. a `Strong` node) that itself has multiple children, because `.format()`
    // on that span visits all of its descendants within one continuous formatting pass,
    // properly flushing the queued newline. That reproduces the real bug: an embedded
    // "\n" followed by a leaked list-marker-alignment prefix on the interior line.
    func testListItemWithHardLineBreakDoesNotLeakAlignmentPrefixOnInteriorLine() {
        let source = "- **First line  \n  Second line**"
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        guard case .list(let items, _) = blocks[0].kind else {
            return XCTFail("Expected list block, got \(blocks[0].kind)")
        }
        // "First line" + the two-space hard-break marker + a real newline, then
        // "Second line" with NO leaked leading-space padding before it.
        XCTAssertEqual(String(items[0].content.characters), "First line  \nSecond line")
    }
}
