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
