import XCTest
@testable import MarkdownPreview

final class MarkdownRendererImageTests: XCTestCase {
    func testRelativeImagePathResolvesAgainstBaseURL() {
        let baseURL = URL(fileURLWithPath: "/Users/example/notes/")
        let source = "![A diagram](diagram.png)"
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        XCTAssertEqual(blocks.count, 1)
        guard case .image(let url, let altText) = blocks[0].kind else {
            return XCTFail("Expected image block, got \(blocks[0].kind)")
        }
        XCTAssertEqual(altText, "A diagram")
        XCTAssertEqual(url.path, "/Users/example/notes/diagram.png")
    }
}
