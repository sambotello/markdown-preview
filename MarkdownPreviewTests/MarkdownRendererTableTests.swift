import XCTest
@testable import MarkdownPreview

final class MarkdownRendererTableTests: XCTestCase {
    private let baseURL = URL(fileURLWithPath: "/tmp")

    func testTableHeadersAndRows() {
        let source = """
        | Name | Age |
        | --- | --- |
        | Alice | 30 |
        | Bob | 25 |
        """
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        XCTAssertEqual(blocks.count, 1)
        guard case .table(let headers, let rows) = blocks[0].kind else {
            return XCTFail("Expected table block, got \(blocks[0].kind)")
        }
        XCTAssertEqual(headers.map { String($0.characters) }, ["Name", "Age"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].map { String($0.characters) }, ["Alice", "30"])
        XCTAssertEqual(rows[1].map { String($0.characters) }, ["Bob", "25"])
    }
}
