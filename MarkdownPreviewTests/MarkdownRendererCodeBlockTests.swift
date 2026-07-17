// MarkdownPreviewTests/MarkdownRendererCodeBlockTests.swift
import XCTest
@testable import MarkdownPreview

final class MarkdownRendererCodeBlockTests: XCTestCase {
    private let baseURL = URL(fileURLWithPath: "/tmp")

    func testFencedCodeBlockWithLanguage() {
        let source = "```swift\nlet x = 1\n```"
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let code, let language) = blocks[0].kind else {
            return XCTFail("Expected code block, got \(blocks[0].kind)")
        }
        XCTAssertEqual(code, "let x = 1\n")
        XCTAssertEqual(language, "swift")
    }

    func testThematicBreak() {
        let source = "Paragraph one.\n\n---\n\nParagraph two."
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].kind, .thematicBreak)
    }
}
