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

    func testImageWithUnresolvableSourceFallsBackToParagraphText() {
        let source = "![A diagram]()"
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph = blocks[0].kind else {
            return XCTFail("Expected paragraph fallback, got \(blocks[0].kind)")
        }
    }

    // Remote images are explicitly out of scope per the spec. `ImageBlockView` calls
    // `NSImage(contentsOf:)` directly in its view body, which for a remote URL would be a
    // synchronous network fetch blocking the main thread — so a non-`file:` scheme must
    // never resolve to an `.image` block. It should fall back the same way an
    // unresolvable (`nil`) source already does: as plain paragraph text.
    func testRemoteImageURLFallsBackToParagraphTextInsteadOfImageBlock() {
        let source = "![x](https://example.com/image.png)"
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph = blocks[0].kind else {
            return XCTFail("Expected paragraph fallback for remote image, got \(blocks[0].kind)")
        }
    }
}
