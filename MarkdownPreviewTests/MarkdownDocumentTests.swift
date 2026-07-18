// MarkdownPreviewTests/MarkdownDocumentTests.swift
import XCTest
@testable import MarkdownPreview

final class MarkdownDocumentTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "# Title".write(to: tempURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testLoadParsesFileIntoBlocks() {
        let document = MarkdownDocument()
        document.load(url: tempURL)

        guard case .loaded(let blocks) = document.state else {
            return XCTFail("Expected loaded state, got \(document.state)")
        }
        XCTAssertEqual(blocks.count, 1)
    }

    func testRejectsUnsupportedExtension() {
        let txtURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        let document = MarkdownDocument()
        document.load(url: txtURL)
        XCTAssertEqual(document.state, .unsupportedFile)
    }

    func testDetectsExternalEdit() {
        let document = MarkdownDocument()
        document.load(url: tempURL)

        let expectation = expectation(description: "reloaded")
        try? "# Updated Title".write(to: tempURL, atomically: true, encoding: .utf8)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if case .loaded(let blocks) = document.state,
               case .heading(_, let text) = blocks.first?.kind,
               String(text.characters) == "Updated Title" {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 2)
        timer.invalidate()
    }
}
