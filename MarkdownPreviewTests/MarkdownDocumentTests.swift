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

    func testIsDirtyReflectsUnsavedChanges() {
        let document = MarkdownDocument()
        document.load(url: tempURL)
        XCTAssertFalse(document.isDirty)

        document.updateDraft("# Changed")
        XCTAssertTrue(document.isDirty)
    }

    func testUpdateDraftRerendersPreviewWithoutTouchingDisk() throws {
        let document = MarkdownDocument()
        document.load(url: tempURL)

        document.updateDraft("# New Heading")

        guard case .loaded(let blocks) = document.state,
              case .heading(_, let text) = blocks.first?.kind else {
            return XCTFail("Expected loaded state with a heading block")
        }
        XCTAssertEqual(String(text.characters), "New Heading")

        let onDisk = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertEqual(onDisk, "# Title")
    }

    func testSaveWritesDraftToDiskAndClearsDirty() throws {
        let document = MarkdownDocument()
        document.load(url: tempURL)
        document.updateDraft("# Saved Content")

        document.save()

        XCTAssertFalse(document.isDirty)
        XCTAssertNil(document.saveError)
        let onDisk = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertEqual(onDisk, "# Saved Content")
    }

    func testExternalChangeWhileDirtySetsPendingConflict() {
        let document = MarkdownDocument()
        document.load(url: tempURL)
        document.updateDraft("# My Edit")

        let expectation = expectation(description: "pending conflict")
        try? "# External Change".write(to: tempURL, atomically: false, encoding: .utf8)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if document.pendingExternalChange != nil {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 2)
        timer.invalidate()

        XCTAssertEqual(document.pendingExternalChange, "# External Change")
        XCTAssertEqual(document.rawText, "# My Edit")
    }

    func testSaveEchoWhileDirtyIsIgnored() throws {
        let document = MarkdownDocument()
        document.load(url: tempURL)

        document.updateDraft("# Saved Version")
        document.save()
        XCTAssertFalse(document.isDirty)

        // Type something new before the watcher's echo of the save above arrives.
        document.updateDraft("# Newer Unsaved Edit")
        XCTAssertTrue(document.isDirty)

        // Re-touch the file with the content that was actually saved (not the
        // newer edit) to simulate that delayed echo as a real file event.
        let noConflictExpectation = expectation(description: "no conflict raised for save echo")
        noConflictExpectation.isInverted = true
        try "# Saved Version".write(to: tempURL, atomically: false, encoding: .utf8)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if document.pendingExternalChange != nil {
                noConflictExpectation.fulfill()
            }
        }
        wait(for: [noConflictExpectation], timeout: 1.0)
        timer.invalidate()

        XCTAssertNil(document.pendingExternalChange)
        XCTAssertEqual(document.rawText, "# Newer Unsaved Edit")
    }

    func testMissingWhileDirtyLeavesStateUnchanged() {
        let document = MarkdownDocument()
        document.load(url: tempURL)
        document.updateDraft("# Unsaved Edit")

        guard case .loaded = document.state else {
            return XCTFail("Expected loaded state before deleting file")
        }

        let staysLoadedExpectation = expectation(description: "state stays loaded while dirty")
        staysLoadedExpectation.isInverted = true
        try? FileManager.default.removeItem(at: tempURL)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if document.state == .fileMissing {
                staysLoadedExpectation.fulfill()
            }
        }
        wait(for: [staysLoadedExpectation], timeout: 1.0)
        timer.invalidate()

        guard case .loaded = document.state else {
            return XCTFail("Expected state to remain loaded, got \(document.state)")
        }
        XCTAssertEqual(document.rawText, "# Unsaved Edit")

        // Recreate the file so tearDown's removeItem doesn't fail.
        try? "# Unsaved Edit".write(to: tempURL, atomically: true, encoding: .utf8)
    }

    func testMissingWhileNotDirtyTransitionsToFileMissing() {
        let document = MarkdownDocument()
        document.load(url: tempURL)

        let expectation = expectation(description: "file missing")
        try? FileManager.default.removeItem(at: tempURL)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if document.state == .fileMissing {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 2)
        timer.invalidate()

        // Recreate the file so tearDown's removeItem doesn't fail.
        try? "Recreated".write(to: tempURL, atomically: true, encoding: .utf8)
    }
}
