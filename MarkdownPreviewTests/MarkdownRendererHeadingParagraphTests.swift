import XCTest
@testable import MarkdownPreview

final class MarkdownRendererHeadingParagraphTests: XCTestCase {
    private let baseURL = URL(fileURLWithPath: "/tmp")

    func testHeadingAndParagraphWithBoldText() {
        let source = "# Title\n\nSome **bold** and plain text."
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        XCTAssertEqual(blocks.count, 2)

        guard case .heading(let level, let text) = blocks[0].kind else {
            return XCTFail("Expected heading block, got \(blocks[0].kind)")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(String(text.characters), "Title")

        guard case .paragraph(let paragraphText) = blocks[1].kind else {
            return XCTFail("Expected paragraph block, got \(blocks[1].kind)")
        }
        XCTAssertEqual(String(paragraphText.characters), "Some bold and plain text.")
        let hasBoldRun = paragraphText.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized }
        XCTAssertTrue(hasBoldRun, "Expected at least one bold run in the paragraph")
    }
}
