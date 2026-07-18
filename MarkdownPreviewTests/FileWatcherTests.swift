import XCTest
@testable import MarkdownPreview

final class FileWatcherTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "Initial".write(to: tempURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testDetectsWriteToFile() {
        let expectation = expectation(description: "changed")
        let watcher = FileWatcher(url: tempURL, gracePeriod: 0.05) { event in
            if case .changed = event { expectation.fulfill() }
        }
        try? "Updated".write(to: tempURL, atomically: true, encoding: .utf8)
        wait(for: [expectation], timeout: 2)
        _ = watcher
    }

    func testToleratesAtomicSaveWithoutReportingMissing() {
        let missingExpectation = expectation(description: "missing")
        missingExpectation.isInverted = true
        let watcher = FileWatcher(url: tempURL, gracePeriod: 0.3) { event in
            if case .missing = event { missingExpectation.fulfill() }
        }
        // `atomically: true` writes a temp file then renames it over the original —
        // a real atomic save, not a simulation.
        try? "Recreated".write(to: tempURL, atomically: true, encoding: .utf8)
        wait(for: [missingExpectation], timeout: 0.5)
        _ = watcher
    }

    func testReportsMissingAfterGracePeriodWithNoRecreate() {
        let missingExpectation = expectation(description: "missing")
        let watcher = FileWatcher(url: tempURL, gracePeriod: 0.05) { event in
            if case .missing = event { missingExpectation.fulfill() }
        }
        try? FileManager.default.removeItem(at: tempURL)
        wait(for: [missingExpectation], timeout: 2)
        _ = watcher
    }
}
