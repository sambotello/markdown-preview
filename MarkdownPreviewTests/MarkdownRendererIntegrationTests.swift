import XCTest
@testable import MarkdownPreview

final class MarkdownRendererIntegrationTests: XCTestCase {
    func testBlockQuote() {
        let baseURL = URL(fileURLWithPath: "/tmp")
        let blocks = MarkdownRenderer.render(markdown: "> Quoted text.", baseURL: baseURL)

        XCTAssertEqual(blocks.count, 1)
        guard case .blockQuote(let inner) = blocks[0].kind else {
            return XCTFail("Expected block quote, got \(blocks[0].kind)")
        }
        guard case .paragraph(let text) = inner.first?.kind else {
            return XCTFail("Expected paragraph inside block quote")
        }
        XCTAssertEqual(String(text.characters), "Quoted text.")
    }

    // Reproduces a bug found during manual verification: two source lines inside a single
    // block-quote paragraph are joined by a CommonMark "soft break". `inlineText(_:)` used
    // to format each inline child independently via `Markup.format()` and string-join the
    // results; formatting a `SoftBreak` node in isolation (outside the continuous pass
    // `.format()` normally runs over a whole subtree) produces "", so the two lines were
    // concatenated with no separator at all ("...text.It should..."). Assert a space now
    // separates them, per CommonMark's soft-break-reflows-as-a-space semantics.
    func testBlockQuoteSoftBreakBetweenLinesRendersAsSpace() {
        let baseURL = URL(fileURLWithPath: "/tmp")
        let source = "> This is a quoted line of text.\n> It should render with an indent and a side bar."
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        XCTAssertEqual(blocks.count, 1)
        guard case .blockQuote(let inner) = blocks[0].kind else {
            return XCTFail("Expected block quote, got \(blocks[0].kind)")
        }
        guard case .paragraph(let text) = inner.first?.kind else {
            return XCTFail("Expected paragraph inside block quote")
        }
        let rendered = String(text.characters)
        XCTAssertEqual(rendered, "This is a quoted line of text. It should render with an indent and a side bar.")
        XCTAssertFalse(rendered.contains("text.It"), "Lines must not be concatenated with no separator")
    }

    func testDocumentWithAllSupportedElements() {
        let source = """
        # Report

        Some **intro** text.

        - Point one
        - Point two

        ```swift
        let x = 1
        ```

        | Col A | Col B |
        | --- | --- |
        | 1 | 2 |

        ![Chart](chart.png)
        """
        let baseURL = URL(fileURLWithPath: "/tmp")
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        let kinds = blocks.map { block -> String in
            switch block.kind {
            case .heading: return "heading"
            case .paragraph: return "paragraph"
            case .list: return "list"
            case .codeBlock: return "codeBlock"
            case .table: return "table"
            case .image: return "image"
            case .blockQuote: return "blockQuote"
            case .thematicBreak: return "thematicBreak"
            }
        }
        XCTAssertEqual(kinds, ["heading", "paragraph", "list", "codeBlock", "table", "image"])
    }
}
