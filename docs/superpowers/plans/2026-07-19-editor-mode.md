# Editor Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a toolbar button that splits the preview window into a Markdown source editor (left) and the existing live preview (right), with explicit (Cmd+S) saving and loss-prevention prompts for unsaved edits.

**Architecture:** Extend the existing per-window `MarkdownDocument` view model with draft/save/dirty/conflict state (rather than a parallel editor object), since conflict detection needs both "what's on disk" and "what's being edited" together. `PreviewWindowView` gains a purely presentational `isEditing` toggle (independent of dirty state) plus alerts that bind to the document's new observable properties. A new `SaveCommand` follows the existing `FileOpenCommand`/`NewWindowCommand` pattern for Cmd+S.

**Tech Stack:** Swift 5, SwiftUI (`@Observable`/`Observation`), AppKit (`NSPasteboard`), XCTest. No new dependencies.

## Global Constraints

- Editing applies only to a file already opened in a window (via Cmd+O, drag & drop, or Finder/Dock open) — no new/untitled-document flow in this pass.
- Saves are explicit (Cmd+S only) — never auto-saved.
- The editor pane is a plain, monospaced `TextEditor` — no Markdown source syntax highlighting.
- The editor/preview split divider is user-resizable via `HSplitView`, default 50/50.
- The editor/preview toggle is per-window state that defaults to `false` (preview-only) for every window.
- The real macOS window close (red traffic-light button / Cmd+W) is NOT intercepted — no unsaved-edits prompt there in this pass.
- This project's Xcode project uses file-system-synchronized groups — new `.swift` files placed under `MarkdownPreview/App/`, `MarkdownPreview/Core/`, or `MarkdownPreviewTests/` are picked up automatically; no `.xcodeproj` editing needed.
- Spec reference: `docs/superpowers/specs/2026-07-19-editor-mode-design.md`.

---

### Task 1: Draft/save/dirty state on `MarkdownDocument`

**Files:**
- Modify: `MarkdownPreview/Core/MarkdownDocument.swift`
- Test: `MarkdownPreviewTests/MarkdownDocumentTests.swift`

**Interfaces:**
- Consumes: nothing new (builds on existing `MarkdownDocument.state`, `rawText`, `url`, `reload()`, `close()`, `load(url:)`).
- Produces (used by later tasks):
  - `var savedText: String? { get }` — last content known to match disk.
  - `var isDirty: Bool { get }` — `rawText != nil && rawText != savedText`.
  - `var saveError: String? { get }` — set when `save()` fails.
  - `func updateDraft(_ text: String)` — updates `rawText` and re-renders `state` from it.
  - `func save()` — writes `rawText` to disk; sets `savedText` on success or `saveError` on failure.
  - `func dismissSaveError()` — clears `saveError`.

- [ ] **Step 1: Write the failing tests**

Add these three tests to `MarkdownPreviewTests/MarkdownDocumentTests.swift`, right before the closing `}` of the `MarkdownDocumentTests` class (after `testDetectsExternalEdit`):

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownDocumentTests`
Expected: BUILD FAILED — `value of type 'MarkdownDocument' has no member 'isDirty'` (and `updateDraft`, `save` used with no-arg form isn't yet defined either).

- [ ] **Step 3: Implement the minimal code**

Replace the full contents of `MarkdownPreview/Core/MarkdownDocument.swift` with:

```swift
// MarkdownPreview/Core/MarkdownDocument.swift
import Foundation
import Observation

@MainActor
@Observable
final class MarkdownDocument {
    enum State: Equatable {
        case empty
        case loaded(blocks: [Block])
        case fileMissing
        case unsupportedFile
        case error(message: String)
    }

    private(set) var state: State = .empty
    private(set) var url: URL?
    private(set) var rawText: String?
    private(set) var savedText: String?
    private(set) var saveError: String?
    private var watcher: FileWatcher?

    private static let supportedExtensions: Set<String> = ["md", "markdown"]

    var blocks: [Block]? {
        if case .loaded(let blocks) = state { blocks } else { nil }
    }

    var isDirty: Bool {
        rawText != nil && rawText != savedText
    }

    func load(url: URL) {
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            watcher = nil
            self.url = nil
            state = .unsupportedFile
            return
        }
        self.url = url
        reload()
        watcher = FileWatcher(url: url) { [weak self] event in
            DispatchQueue.main.async {
                guard let self else { return }
                switch event {
                case .changed:
                    self.reload()
                case .missing:
                    self.state = .fileMissing
                }
            }
        }
    }

    func close() {
        watcher = nil
        url = nil
        rawText = nil
        savedText = nil
        saveError = nil
        state = .empty
    }

    func updateDraft(_ text: String) {
        guard let url else { return }
        rawText = text
        state = .loaded(blocks: MarkdownRenderer.render(markdown: text, baseURL: url.deletingLastPathComponent()))
    }

    func save() {
        guard let url, let rawText else { return }
        do {
            try rawText.write(to: url, atomically: true, encoding: .utf8)
            savedText = rawText
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    func dismissSaveError() {
        saveError = nil
    }

    private func reload() {
        guard let url else { return }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let baseURL = url.deletingLastPathComponent()
            rawText = source
            savedText = source
            state = .loaded(blocks: MarkdownRenderer.render(markdown: source, baseURL: baseURL))
        } catch {
            rawText = nil
            savedText = nil
            state = .error(message: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownDocumentTests`
Expected: all tests PASS, including the pre-existing ones (`testLoadParsesFileIntoBlocks`, `testRejectsUnsupportedExtension`, `testRejectingUnsupportedFileStopsWatchingPreviousFile`, `testDetectsExternalEdit`).

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/MarkdownDocument.swift MarkdownPreviewTests/MarkdownDocumentTests.swift
git commit -m "feat: add draft, save, and dirty tracking to MarkdownDocument"
```

---

### Task 2: External-change conflict & dirty-aware missing-file handling

**Files:**
- Modify: `MarkdownPreview/Core/MarkdownDocument.swift`
- Test: `MarkdownPreviewTests/MarkdownDocumentTests.swift`

**Interfaces:**
- Consumes: `isDirty`, `savedText`, `rawText`, `reload()` from Task 1.
- Produces (used by Task 5):
  - `var pendingExternalChange: String? { get }` — set when the file changes on disk while dirty.
  - `func keepMyEdits()` — clears `pendingExternalChange`, keeps the draft.
  - `func reloadFromDisk()` — clears `pendingExternalChange`, discards the draft, reloads from disk.

- [ ] **Step 1: Write the failing tests**

Add these three tests to `MarkdownPreviewTests/MarkdownDocumentTests.swift`, after the tests added in Task 1:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownDocumentTests`
Expected: BUILD FAILED — `value of type 'MarkdownDocument' has no member 'pendingExternalChange'`.

- [ ] **Step 3: Implement the minimal code**

In `MarkdownPreview/Core/MarkdownDocument.swift`, add a new stored property right after `saveError`:

```swift
    private(set) var saveError: String?
    private(set) var pendingExternalChange: String?
```

Update `close()` to also clear it:

```swift
    func close() {
        watcher = nil
        url = nil
        rawText = nil
        savedText = nil
        saveError = nil
        pendingExternalChange = nil
        state = .empty
    }
```

Update the watcher closure inside `load(url:)` to route through the new dirty-aware handlers:

```swift
        watcher = FileWatcher(url: url) { [weak self] event in
            DispatchQueue.main.async {
                guard let self else { return }
                switch event {
                case .changed:
                    self.handleExternalChange()
                case .missing:
                    if !self.isDirty {
                        self.state = .fileMissing
                    }
                }
            }
        }
```

Add these new methods (near `dismissSaveError()`):

```swift
    func keepMyEdits() {
        pendingExternalChange = nil
    }

    func reloadFromDisk() {
        pendingExternalChange = nil
        reload()
    }

    private func handleExternalChange() {
        guard let url, let newContent = try? String(contentsOf: url, encoding: .utf8) else { return }
        if newContent == savedText {
            return
        }
        if isDirty {
            pendingExternalChange = newContent
        } else {
            reload()
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownDocumentTests`
Expected: all tests PASS, including everything from Task 1 and the pre-existing tests.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/MarkdownDocument.swift MarkdownPreviewTests/MarkdownDocumentTests.swift
git commit -m "feat: reconcile external file changes and deletions against unsaved edits"
```

---

### Task 3: `Cmd+S` save command

**Files:**
- Create: `MarkdownPreview/App/SaveCommand.swift`
- Modify: `MarkdownPreview/MarkdownPreviewApp.swift`

**Interfaces:**
- Consumes: `FocusedValues.markdownDocument` (existing), `MarkdownDocument.isDirty`/`save()` (Task 1).
- Produces: nothing new consumed by later tasks (this is a leaf UI wiring task).

No automated test for this task — consistent with the existing `FileOpenCommand`/`NewWindowCommand`, which also have no test coverage (this project has no UI/Commands test target). Verified manually in Step 3 below.

- [ ] **Step 1: Create the command**

Create `MarkdownPreview/App/SaveCommand.swift`:

```swift
// MarkdownPreview/App/SaveCommand.swift
import SwiftUI

struct SaveCommand: View {
    @FocusedValue(\.markdownDocument) private var focusedDocument

    var body: some View {
        Button("Save") {
            focusedDocument?.save()
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(focusedDocument?.isDirty != true)
    }
}
```

- [ ] **Step 2: Wire it into the app's commands**

In `MarkdownPreview/MarkdownPreviewApp.swift`, replace the full file contents with:

```swift
// MarkdownPreview/MarkdownPreviewApp.swift
import SwiftUI

@main
struct MarkdownPreviewApp: App {
    var body: some Scene {
        WindowGroup(id: "preview", for: URL.self) { $fileURL in
            PreviewWindowView(fileURL: $fileURL)
                .onOpenURL { url in
                    fileURL = url
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                NewWindowCommand()
                FileOpenCommand()
            }
            CommandGroup(replacing: .saveItem) {
                SaveCommand()
            }
        }
    }
}
```

- [ ] **Step 3: Build and manually verify**

Run: `xcodebuild -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -configuration Debug build`
Expected: BUILD SUCCEEDED.

Then open the project in Xcode (Cmd+R), open a markdown file, and confirm:
- The File menu shows a "Save" item bound to Cmd+S.
- It's disabled immediately after opening a file (nothing is dirty yet).

- [ ] **Step 4: Commit**

```bash
git add MarkdownPreview/App/SaveCommand.swift MarkdownPreview/MarkdownPreviewApp.swift
git commit -m "feat: add Cmd+S save command"
```

---

### Task 4: Split editor/preview toolbar toggle

**Files:**
- Modify: `MarkdownPreview/Views/PreviewWindowView.swift`

**Interfaces:**
- Consumes: `MarkdownDocument.rawText`, `updateDraft(_:)`, `blocks` (Task 1 and pre-existing).
- Produces (used by Task 5): the `isEditing` state and `editorPane` view are extended, not replacing their names, in Task 5.

No automated test for this task — `PreviewWindowView` (like the rest of `MarkdownPreview/Views` and `MarkdownPreview/App`) has no existing test coverage; this project's test target only covers `Core/`. Verified manually in Step 2 below.

- [ ] **Step 1: Implement the split view and toolbar toggle**

Replace the full contents of `MarkdownPreview/Views/PreviewWindowView.swift` with:

```swift
// MarkdownPreview/Views/PreviewWindowView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PreviewWindowView: View {
    @Binding var fileURL: URL?
    @State private var document = MarkdownDocument()
    @State private var isImporterPresented = false
    @State private var isEditing = false

    private static let markdownContentTypes: [UTType] =
        ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        content
            .navigationTitle(windowTitle)
            .toolbar {
                ToolbarItem {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Open", systemImage: "doc.badge.plus")
                    }
                }
                if document.blocks != nil {
                    ToolbarItem {
                        Button {
                            isEditing.toggle()
                        } label: {
                            Label(isEditing ? "Preview Only" : "Edit", systemImage: isEditing ? "eye" : "square.and.pencil")
                        }
                    }
                }
                if let rawText = document.rawText {
                    ToolbarItem {
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(rawText, forType: .string)
                        } label: {
                            Label("Copy Markdown", systemImage: "doc.on.doc")
                        }
                    }
                }
                if let blocks = document.blocks {
                    ToolbarItem {
                        Button {
                            copyFormatted(blocks: blocks)
                        } label: {
                            Label("Copy Formatted", systemImage: "doc.richtext")
                        }
                    }
                }
                if document.state != .empty {
                    ToolbarItem {
                        Button {
                            document.close()
                            fileURL = nil
                        } label: {
                            Label("Close", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: Self.markdownContentTypes) { result in
                if case .success(let url) = result {
                    fileURL = url
                    document.load(url: url)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                fileURL = url
                document.load(url: url)
                return true
            }
            .focusedSceneValue(\.markdownDocument, document)
            .onAppear {
                if let fileURL, document.url == nil {
                    document.load(url: fileURL)
                }
            }
            .onChange(of: fileURL) { _, newURL in
                if let newURL, document.url != newURL {
                    document.load(url: newURL)
                }
            }
    }

    private func copyFormatted(blocks: [Block]) {
        let attributed = MarkdownRichTextExporter.makeAttributedString(for: blocks)
        let range = NSRange(location: 0, length: attributed.length)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let rtf = attributed.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let html = try? attributed.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
            pasteboard.setData(html, forType: .html)
        }
        pasteboard.setString(attributed.string, forType: .string)
    }

    private var windowTitle: String {
        guard let name = document.url?.lastPathComponent else { return "MarkdownPreview" }
        return "MarkdownPreview — \(name)"
    }

    @ViewBuilder
    private var content: some View {
        switch document.state {
        case .empty:
            DropZoneView()
        case .loaded(let blocks):
            if isEditing {
                HSplitView {
                    editorPane
                    MarkdownView(blocks: blocks)
                }
            } else {
                MarkdownView(blocks: blocks)
            }
        case .fileMissing:
            MessageView(systemImage: "questionmark.folder", message: "File no longer available.")
        case .unsupportedFile:
            MessageView(systemImage: "xmark.circle", message: "Not a markdown file.")
        case .error(let message):
            MessageView(systemImage: "exclamationmark.triangle", message: message)
        }
    }

    private var editorPane: some View {
        TextEditor(text: Binding(
            get: { document.rawText ?? "" },
            set: { document.updateDraft($0) }
        ))
        .font(.system(.body, design: .monospaced))
    }
}
```

- [ ] **Step 2: Build and manually verify**

Run: `xcodebuild -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -configuration Debug build`
Expected: BUILD SUCCEEDED.

Then open the project in Xcode (Cmd+R) and confirm:
- Opening a markdown file shows the preview as before, with a new "Edit" toolbar button.
- Tapping "Edit" splits the window into a monospaced text editor (left) and the live preview (right); the button now reads "Preview Only".
- Typing in the editor updates the preview immediately, without writing to the file on disk (check the file's mtime/contents outside the app).
- Dragging the divider resizes both panes.
- Tapping "Preview Only" hides the editor pane; toggling "Edit" again shows the same in-progress (unsaved) text you typed, not the original disk content.
- The "Edit" button does not appear for the empty drop-zone, file-missing, unsupported-file, or error states.

- [ ] **Step 3: Commit**

```bash
git add MarkdownPreview/Views/PreviewWindowView.swift
git commit -m "feat: add split editor/preview toolbar toggle"
```

---

### Task 5: Unsaved-edit guards and alerts

**Files:**
- Modify: `MarkdownPreview/Views/PreviewWindowView.swift`

**Interfaces:**
- Consumes: `MarkdownDocument.isDirty`, `save()`, `saveError`, `dismissSaveError()` (Task 1); `pendingExternalChange`, `keepMyEdits()`, `reloadFromDisk()` (Task 2); `isEditing`, `editorPane` (Task 4).
- Produces: nothing consumed by later tasks (final task in this plan).

No automated test for this task, for the same reason as Task 4. Verified manually in Step 2 below.

- [ ] **Step 1: Implement the guards and alerts**

Replace the full contents of `MarkdownPreview/Views/PreviewWindowView.swift` with:

```swift
// MarkdownPreview/Views/PreviewWindowView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PreviewWindowView: View {
    @Binding var fileURL: URL?
    @State private var document = MarkdownDocument()
    @State private var isImporterPresented = false
    @State private var isEditing = false
    @State private var pendingAction: PendingAction?

    private enum PendingAction {
        case close
        case open(URL)
    }

    private static let markdownContentTypes: [UTType] =
        ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        content
            .navigationTitle(windowTitle)
            .toolbar {
                ToolbarItem {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Open", systemImage: "doc.badge.plus")
                    }
                }
                if document.blocks != nil {
                    ToolbarItem {
                        Button {
                            isEditing.toggle()
                        } label: {
                            Label(isEditing ? "Preview Only" : "Edit", systemImage: isEditing ? "eye" : "square.and.pencil")
                        }
                    }
                }
                if let rawText = document.rawText {
                    ToolbarItem {
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(rawText, forType: .string)
                        } label: {
                            Label("Copy Markdown", systemImage: "doc.on.doc")
                        }
                    }
                }
                if let blocks = document.blocks {
                    ToolbarItem {
                        Button {
                            copyFormatted(blocks: blocks)
                        } label: {
                            Label("Copy Formatted", systemImage: "doc.richtext")
                        }
                    }
                }
                if document.state != .empty {
                    ToolbarItem {
                        Button {
                            requestClose()
                        } label: {
                            Label("Close", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: Self.markdownContentTypes) { result in
                if case .success(let url) = result {
                    requestOpen(url: url)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                requestOpen(url: url)
                return true
            }
            .focusedSceneValue(\.markdownDocument, document)
            .onAppear {
                if let fileURL, document.url == nil {
                    document.load(url: fileURL)
                }
            }
            .onChange(of: fileURL) { _, newURL in
                if let newURL, document.url != newURL {
                    document.load(url: newURL)
                }
            }
            .alert(
                "Unsaved Changes",
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { isPresented in if !isPresented { pendingAction = nil } }
                ),
                presenting: pendingAction
            ) { action in
                Button("Save") {
                    document.save()
                    if document.saveError == nil {
                        resolve(action)
                    } else {
                        pendingAction = nil
                    }
                }
                Button("Discard", role: .destructive) {
                    resolve(action)
                }
                Button("Cancel", role: .cancel) {
                    pendingAction = nil
                }
            } message: { _ in
                Text("This file has unsaved changes. Do you want to save them first?")
            }
            .alert(
                "File Changed on Disk",
                isPresented: Binding(
                    get: { document.pendingExternalChange != nil },
                    set: { isPresented in if !isPresented { document.keepMyEdits() } }
                )
            ) {
                Button("Keep My Edits") {
                    document.keepMyEdits()
                }
                Button("Reload From Disk", role: .destructive) {
                    document.reloadFromDisk()
                }
            } message: {
                Text("This file was changed by another application. Do you want to keep your edits or reload the file from disk?")
            }
            .alert(
                "Couldn't Save File",
                isPresented: Binding(
                    get: { document.saveError != nil },
                    set: { isPresented in if !isPresented { document.dismissSaveError() } }
                )
            ) {
                Button("OK", role: .cancel) {
                    document.dismissSaveError()
                }
            } message: {
                Text(document.saveError ?? "")
            }
    }

    private func requestClose() {
        if document.isDirty {
            pendingAction = .close
        } else {
            performClose()
        }
    }

    private func requestOpen(url: URL) {
        if document.isDirty {
            pendingAction = .open(url)
        } else {
            performOpen(url: url)
        }
    }

    private func resolve(_ action: PendingAction) {
        pendingAction = nil
        switch action {
        case .close:
            performClose()
        case .open(let url):
            performOpen(url: url)
        }
    }

    private func performClose() {
        document.close()
        fileURL = nil
        isEditing = false
    }

    private func performOpen(url: URL) {
        fileURL = url
        document.load(url: url)
    }

    private func copyFormatted(blocks: [Block]) {
        let attributed = MarkdownRichTextExporter.makeAttributedString(for: blocks)
        let range = NSRange(location: 0, length: attributed.length)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let rtf = attributed.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let html = try? attributed.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
            pasteboard.setData(html, forType: .html)
        }
        pasteboard.setString(attributed.string, forType: .string)
    }

    private var windowTitle: String {
        guard let name = document.url?.lastPathComponent else { return "MarkdownPreview" }
        return "MarkdownPreview — \(name)"
    }

    @ViewBuilder
    private var content: some View {
        switch document.state {
        case .empty:
            DropZoneView()
        case .loaded(let blocks):
            if isEditing {
                HSplitView {
                    editorPane
                    MarkdownView(blocks: blocks)
                }
            } else {
                MarkdownView(blocks: blocks)
            }
        case .fileMissing:
            MessageView(systemImage: "questionmark.folder", message: "File no longer available.")
        case .unsupportedFile:
            MessageView(systemImage: "xmark.circle", message: "Not a markdown file.")
        case .error(let message):
            MessageView(systemImage: "exclamationmark.triangle", message: message)
        }
    }

    private var editorPane: some View {
        TextEditor(text: Binding(
            get: { document.rawText ?? "" },
            set: { document.updateDraft($0) }
        ))
        .font(.system(.body, design: .monospaced))
    }
}
```

- [ ] **Step 2: Build and manually verify**

Run: `xcodebuild -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -configuration Debug build`
Expected: BUILD SUCCEEDED.

Then open the project in Xcode (Cmd+R) and confirm each scenario:
- **Close while dirty:** open a file, enter Edit mode, type a change, tap the toolbar Close button → "Unsaved Changes" alert appears. "Cancel" leaves the document open and dirty. "Discard" closes without saving. "Save" saves to disk, then closes.
- **Open-new-file while dirty:** with unsaved edits, use the toolbar Open button (or drag a different file onto the window) → same "Unsaved Changes" alert; "Save" saves the current file before switching, "Discard" switches without saving, "Cancel" stays on the current file.
- **External conflict:** with unsaved edits, modify the same file in another app (e.g. TextEdit) → "File Changed on Disk" alert appears. "Keep My Edits" dismisses it and leaves your draft as-is (still dirty). "Reload From Disk" replaces your draft with the external content.
- **Save failure:** make the file's directory temporarily unwritable (e.g. `chmod 555` on its parent folder), make an edit, and press Cmd+S → "Couldn't Save File" alert appears with the underlying error message; the draft and dirty state are unaffected, so Cmd+S can be retried after restoring permissions.
- **Close while clean:** with no unsaved edits, the toolbar Close button closes immediately with no alert (unchanged from today).

- [ ] **Step 3: Commit**

```bash
git add MarkdownPreview/Views/PreviewWindowView.swift
git commit -m "feat: guard unsaved edits against close, open, external changes, and save failures"
```
