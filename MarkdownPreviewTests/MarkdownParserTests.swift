import XCTest
import Markdown
@testable import MarkdownPreview

final class MarkdownParserTests: XCTestCase {
    func testParsesHeadingAndParagraphAsSeparateChildren() {
        let document = MarkdownParser.parse("# Title\n\nBody text.")
        let children = Array(document.children)

        XCTAssertEqual(children.count, 2)
        XCTAssertTrue(children[0] is Heading)
        XCTAssertTrue(children[1] is Paragraph)
    }
}
