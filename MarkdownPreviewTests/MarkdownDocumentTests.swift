// MarkdownPreviewTests/MarkdownDocumentTests.swift
import XCTest
@testable import MarkdownPreview

@MainActor
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

    func testRejectingUnsupportedFileStopsWatchingPreviousFile() {
        let document = MarkdownDocument()
        document.load(url: tempURL)

        guard case .loaded = document.state else {
            return XCTFail("Expected loaded state before testing rejection")
        }

        let txtURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        document.load(url: txtURL)
        XCTAssertEqual(document.state, .unsupportedFile)

        // Modify the original file; if the old watcher is still running, this would
        // eventually flip state away from .unsupportedFile.
        try? "# Changed after rejection".write(to: tempURL, atomically: true, encoding: .utf8)

        let stillRejectedExpectation = expectation(description: "state stays unsupportedFile")
        stillRejectedExpectation.isInverted = true
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if document.state != .unsupportedFile {
                stillRejectedExpectation.fulfill()
            }
        }
        wait(for: [stillRejectedExpectation], timeout: 1.0)
        timer.invalidate()
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
