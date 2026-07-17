# Live Markdown Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS app that watches a markdown file on disk and renders a live, fully native SwiftUI preview of it, with support for headings, lists, bold/italic/links/inline code, fenced code blocks, tables, and images.

**Architecture:** Core parsing/rendering/file-watching logic lives in plain, UI-independent Swift types under `MarkdownPreview/Core/` (auto-included in the app target via Xcode's synchronized-folder mechanism, and testable via `@testable import MarkdownPreview` from a new `MarkdownPreviewTests` target). `swift-markdown` parses source text into an AST; a `MarkupVisitor` walks it into a plain `[Block]` model; SwiftUI views under `MarkdownPreview/Views/` render `[Block]`. Each window owns its own `MarkdownDocument` (file URL + parsed state) and `FileWatcher`.

**Tech Stack:** SwiftUI (macOS 26.5+, Swift 5.0), `apple/swift-markdown` (Swift Package, branch `main`), XCTest.

## Global Constraints

- Deployment target: macOS 26.5+. Swift version: 5.0. Bundle id: `com.sambotello.MarkdownPreview` (all unchanged from the existing project).
- No external dependency besides `apple/swift-markdown` — do not add other markdown/HTML/WebView libraries.
- Accepted file extensions: exactly `md` and `markdown` (case-insensitive), everywhere a filter or extension check appears.
- File-missing detection grace period: exactly `500ms` (`0.5` seconds) in production code; tests may inject a shorter value through `FileWatcher`'s `gracePeriod` parameter to stay fast.
- No `WebView`/`WKWebView` anywhere — all rendering is native SwiftUI views.
- This project uses Xcode's **file-system-synchronized groups** (`PBXFileSystemSynchronizedRootGroup`) for the `MarkdownPreview` folder — any file placed anywhere under `MarkdownPreview/` is automatically compiled into the `MarkdownPreview` target with no `project.pbxproj` editing required. The same will be true of `MarkdownPreviewTests/` once Task 0 creates that target. Do not hand-edit `project.pbxproj` for adding/removing source files — only Task 0's one-time GUI steps touch it directly.
- If a `swift-markdown` symbol name in this plan doesn't match what Xcode's autocomplete/Quick Help shows (library APIs occasionally shift point releases), trust Xcode over this document and adjust the one call site — the surrounding test will tell you immediately if the fix was right.

---

## Task 0: Project setup — add swift-markdown and a test target

This project currently has no test target and no external dependencies (confirmed by reading `project.pbxproj` — it has one native target, `MarkdownPreview`, with an empty `packageProductDependencies` list). Both additions below require Xcode's project-file wiring (package references and a new native target with its own build phases), which is safe to do once via Xcode's GUI but risky to hand-edit blindly. Everything after this task is plain file creation.

**Files:**
- Modify: `MarkdownPreview.xcodeproj/project.pbxproj` (via Xcode GUI only, not by hand)

- [ ] **Step 1: Add the swift-markdown package dependency**

In Xcode, open `MarkdownPreview.xcodeproj`. Select the top-level **MarkdownPreview** project in the navigator, select the **MarkdownPreview** project (not target) in the editor, go to the **Package Dependencies** tab, click **+**, and enter:
- Package URL: `https://github.com/apple/swift-markdown`
- Dependency Rule: **Branch** — `main` (swift-markdown's tagged releases lag behind `main`; pinning to `main` avoids this plan depending on a specific version number that may already be stale)

When prompted to choose a target, add the **Markdown** product to the **MarkdownPreview** target.

- [ ] **Step 2: Create the unit test target**

File > New > Target… > macOS > **Unit Testing Bundle**. Set:
- Product Name: `MarkdownPreviewTests`
- Target to be Tested: `MarkdownPreview`

Click Finish. When Xcode asks to add the new target to the current scheme's Test action, accept.

- [ ] **Step 3: Delete the auto-generated placeholder test file**

Xcode creates `MarkdownPreviewTests/MarkdownPreviewTests.swift` with a template `testExample()` method. Delete this file (right-click > Delete > Move to Trash) — every task below adds its own real test file.

- [ ] **Step 4: Verify the project structure from the command line**

Run: `xcodebuild -list -project MarkdownPreview.xcodeproj`
Expected: output includes both `MarkdownPreview` and `MarkdownPreviewTests` under `Targets:`.

- [ ] **Step 5: Verify the test target runs (with zero tests)**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS'`
Expected: build succeeds and output ends with `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MarkdownPreview.xcodeproj
git commit -m "chore: add swift-markdown dependency and MarkdownPreviewTests target"
```

---

## Task 1: Block model

The plain data model that `MarkdownRenderer` produces and every view consumes. No SwiftUI, no swift-markdown — a pure value type so it's trivial to test and reason about in isolation.

**Files:**
- Create: `MarkdownPreview/Core/Block.swift`
- Test: `MarkdownPreviewTests/BlockTests.swift`

**Interfaces:**
- Produces: `Block` (Equatable struct), `Block.Kind` (Equatable enum with cases `.heading(level: Int, text: AttributedString)`, `.paragraph(text: AttributedString)`, `.codeBlock(code: String, language: String?)`, `.list(items: [Block.ListItem], isOrdered: Bool)`, `.table(headers: [AttributedString], rows: [[AttributedString]])`, `.image(url: URL, altText: String)`, `.blockQuote(blocks: [Block])`, `.thematicBreak`), `Block.ListItem` (Equatable struct with `content: AttributedString`, `children: [Block]`).

- [ ] **Step 1: Write the failing test**

```swift
// MarkdownPreviewTests/BlockTests.swift
import XCTest
@testable import MarkdownPreview

final class BlockTests: XCTestCase {
    func testEqualParagraphBlocksAreEqual() {
        let a = Block(kind: .paragraph(text: AttributedString("Hello")))
        let b = Block(kind: .paragraph(text: AttributedString("Hello")))
        XCTAssertEqual(a, b)
    }

    func testDifferentKindsAreNotEqual() {
        let heading = Block(kind: .heading(level: 1, text: AttributedString("Title")))
        let paragraph = Block(kind: .paragraph(text: AttributedString("Title")))
        XCTAssertNotEqual(heading, paragraph)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/BlockTests`
Expected: FAIL — `Block` is not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MarkdownPreview/Core/Block.swift
import Foundation

struct Block: Equatable {
    enum Kind: Equatable {
        case heading(level: Int, text: AttributedString)
        case paragraph(text: AttributedString)
        case codeBlock(code: String, language: String?)
        case list(items: [ListItem], isOrdered: Bool)
        case table(headers: [AttributedString], rows: [[AttributedString]])
        case image(url: URL, altText: String)
        case blockQuote(blocks: [Block])
        case thematicBreak
    }

    struct ListItem: Equatable {
        let content: AttributedString
        let children: [Block]
    }

    let kind: Kind
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/BlockTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/Block.swift MarkdownPreviewTests/BlockTests.swift
git commit -m "feat: add Block model for parsed markdown content"
```

---

## Task 2: MarkdownParser

Thin wrapper around `swift-markdown`'s document parser — isolates the one external-library call site for parsing.

**Files:**
- Create: `MarkdownPreview/Core/MarkdownParser.swift`
- Test: `MarkdownPreviewTests/MarkdownParserTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `enum MarkdownParser { static func parse(_ source: String) -> Document }` (`Document` is `swift-markdown`'s `Markdown.Document` type).

- [ ] **Step 1: Write the failing test**

```swift
// MarkdownPreviewTests/MarkdownParserTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownParserTests`
Expected: FAIL — `MarkdownParser` is not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MarkdownPreview/Core/MarkdownParser.swift
import Markdown

enum MarkdownParser {
    static func parse(_ source: String) -> Document {
        Document(parsing: source)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownParserTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/MarkdownParser.swift MarkdownPreviewTests/MarkdownParserTests.swift
git commit -m "feat: add MarkdownParser wrapping swift-markdown"
```

---

## Task 3: MarkdownRenderer — headings and paragraphs

Introduces `MarkdownRenderer`, a `MarkupVisitor` that walks the AST into `[Block]`. This task covers the two most common block types plus the inline-text strategy every later block type reuses: extract each node's inline markdown source via `.format()` on its children, then hand that to Foundation's `AttributedString(markdown:)` initializer — this reuses Apple's native inline parser (bold/italic/links/inline code) instead of hand-rolling one, while `swift-markdown` handles block structure.

**Files:**
- Create: `MarkdownPreview/Core/MarkdownRenderer.swift`
- Test: `MarkdownPreviewTests/MarkdownRendererHeadingParagraphTests.swift`

**Interfaces:**
- Consumes: `Block`, `Block.Kind` ([[Task 1]]); `Document` from `MarkdownParser.parse(_:)` ([[Task 2]]).
- Produces: `struct MarkdownRenderer: MarkupVisitor` with `static func render(markdown source: String, baseURL: URL) -> [Block]` — this is the one entry point every other task's tests and the app's view layer call.

- [ ] **Step 1: Write the failing test**

```swift
// MarkdownPreviewTests/MarkdownRendererHeadingParagraphTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererHeadingParagraphTests`
Expected: FAIL — `MarkdownRenderer` is not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MarkdownPreview/Core/MarkdownRenderer.swift
import Foundation
import Markdown

struct MarkdownRenderer: MarkupVisitor {
    typealias Result = [Block]

    let baseURL: URL

    static func render(markdown source: String, baseURL: URL) -> [Block] {
        let document = MarkdownParser.parse(source)
        var renderer = MarkdownRenderer(baseURL: baseURL)
        return document.children.flatMap { renderer.visit($0) }
    }

    mutating func defaultVisit(_ markup: Markup) -> [Block] {
        []
    }

    mutating func visitHeading(_ heading: Heading) -> [Block] {
        [Block(kind: .heading(level: heading.level, text: inlineText(heading)))]
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> [Block] {
        [Block(kind: .paragraph(text: inlineText(paragraph)))]
    }

    func inlineText(_ markup: Markup) -> AttributedString {
        let source = markup.children.map { $0.format() }.joined()
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(markup.plainText)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererHeadingParagraphTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/MarkdownRenderer.swift MarkdownPreviewTests/MarkdownRendererHeadingParagraphTests.swift
git commit -m "feat: render headings and paragraphs with inline styling"
```

---

## Task 4: MarkdownRenderer — code blocks and thematic breaks

**Files:**
- Modify: `MarkdownPreview/Core/MarkdownRenderer.swift`
- Test: `MarkdownPreviewTests/MarkdownRendererCodeBlockTests.swift`

**Interfaces:**
- Consumes: `MarkdownRenderer.render(markdown:baseURL:)` ([[Task 3]]).
- Produces: no new public surface — adds `.codeBlock` and `.thematicBreak` case coverage to the same renderer.

- [ ] **Step 1: Write the failing test**

```swift
// MarkdownPreviewTests/MarkdownRendererCodeBlockTests.swift
import XCTest
@testable import MarkdownPreview

final class MarkdownRendererCodeBlockTests: XCTestCase {
    private let baseURL = URL(fileURLWithPath: "/tmp")

    func testFencedCodeBlockWithLanguage() {
        let source = "```swift\nlet x = 1\n```"
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let code, let language) = blocks[0].kind else {
            return XCTFail("Expected code block, got \(blocks[0].kind)")
        }
        XCTAssertEqual(code, "let x = 1\n")
        XCTAssertEqual(language, "swift")
    }

    func testThematicBreak() {
        let source = "Paragraph one.\n\n---\n\nParagraph two."
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].kind, .thematicBreak)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererCodeBlockTests`
Expected: FAIL — both blocks render as empty (`defaultVisit` returns `[]`), so `blocks.count` is 0.

- [ ] **Step 3: Write minimal implementation**

Add these two methods to `MarkdownRenderer` in `MarkdownPreview/Core/MarkdownRenderer.swift`:

```swift
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> [Block] {
        [Block(kind: .codeBlock(code: codeBlock.code, language: codeBlock.language))]
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> [Block] {
        [Block(kind: .thematicBreak)]
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererCodeBlockTests`
Expected: PASS. If the exact code-block string differs (e.g. no trailing newline), adjust the assertion to match what `swift-markdown` actually returns — the test failure will show the real value.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/MarkdownRenderer.swift MarkdownPreviewTests/MarkdownRendererCodeBlockTests.swift
git commit -m "feat: render fenced code blocks and thematic breaks"
```

---

## Task 5: MarkdownRenderer — lists (ordered, unordered, nested)

**Files:**
- Modify: `MarkdownPreview/Core/MarkdownRenderer.swift`
- Test: `MarkdownPreviewTests/MarkdownRendererListTests.swift`

**Interfaces:**
- Consumes: `MarkdownRenderer.render(markdown:baseURL:)`, `Block.ListItem` ([[Task 1]]).
- Produces: `.list` case coverage; adds a private `makeListItem(_:) -> Block.ListItem` helper other tasks don't call directly.

- [ ] **Step 1: Write the failing test**

```swift
// MarkdownPreviewTests/MarkdownRendererListTests.swift
import XCTest
@testable import MarkdownPreview

final class MarkdownRendererListTests: XCTestCase {
    private let baseURL = URL(fileURLWithPath: "/tmp")

    func testUnorderedListWithNestedList() {
        let source = """
        - Item one
        - Item two
          - Nested item
        """
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items, let isOrdered) = blocks[0].kind else {
            return XCTFail("Expected list block, got \(blocks[0].kind)")
        }
        XCTAssertFalse(isOrdered)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(String(items[0].content.characters), "Item one")
        XCTAssertEqual(String(items[1].content.characters), "Item two")
        XCTAssertEqual(items[1].children.count, 1)

        guard case .list(let nestedItems, _) = items[1].children[0].kind else {
            return XCTFail("Expected nested list block, got \(items[1].children[0].kind)")
        }
        XCTAssertEqual(String(nestedItems[0].content.characters), "Nested item")
    }

    func testOrderedList() {
        let source = "1. First\n2. Second"
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        guard case .list(let items, let isOrdered) = blocks[0].kind else {
            return XCTFail("Expected list block, got \(blocks[0].kind)")
        }
        XCTAssertTrue(isOrdered)
        XCTAssertEqual(items.map { String($0.content.characters) }, ["First", "Second"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererListTests`
Expected: FAIL — lists render as empty (`defaultVisit` returns `[]`).

- [ ] **Step 3: Write minimal implementation**

Add these methods to `MarkdownRenderer`:

```swift
    mutating func visitUnorderedList(_ list: UnorderedList) -> [Block] {
        [Block(kind: .list(items: list.listItems.map { makeListItem($0) }, isOrdered: false))]
    }

    mutating func visitOrderedList(_ list: OrderedList) -> [Block] {
        [Block(kind: .list(items: list.listItems.map { makeListItem($0) }, isOrdered: true))]
    }

    private mutating func makeListItem(_ item: ListItem) -> Block.ListItem {
        var content = AttributedString("")
        var children: [Block] = []
        for child in item.children {
            if let paragraph = child as? Paragraph {
                content += inlineText(paragraph)
            } else {
                children += visit(child)
            }
        }
        return Block.ListItem(content: content, children: children)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererListTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/MarkdownRenderer.swift MarkdownPreviewTests/MarkdownRendererListTests.swift
git commit -m "feat: render ordered, unordered, and nested lists"
```

---

## Task 6: MarkdownRenderer — tables

**Files:**
- Modify: `MarkdownPreview/Core/MarkdownRenderer.swift`
- Test: `MarkdownPreviewTests/MarkdownRendererTableTests.swift`

**Interfaces:**
- Consumes: `MarkdownRenderer.render(markdown:baseURL:)`.
- Produces: `.table` case coverage.

- [ ] **Step 1: Write the failing test**

```swift
// MarkdownPreviewTests/MarkdownRendererTableTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererTableTests`
Expected: FAIL — tables render as empty (`defaultVisit` returns `[]`).

- [ ] **Step 3: Write minimal implementation**

Add this method to `MarkdownRenderer`:

```swift
    mutating func visitTable(_ table: Table) -> [Block] {
        let headers = table.head.cells.map { inlineText($0) }
        let rows = table.body.rows.map { row in row.cells.map { inlineText($0) } }
        return [Block(kind: .table(headers: headers, rows: rows))]
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererTableTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/MarkdownRenderer.swift MarkdownPreviewTests/MarkdownRendererTableTests.swift
git commit -m "feat: render GFM tables"
```

---

## Task 7: MarkdownRenderer — images

Resolves relative image paths against the source file's containing directory, per the spec.

**Files:**
- Modify: `MarkdownPreview/Core/MarkdownRenderer.swift`
- Test: `MarkdownPreviewTests/MarkdownRendererImageTests.swift`

**Interfaces:**
- Consumes: `MarkdownRenderer.render(markdown:baseURL:)`; `baseURL` is the directory containing the markdown source file.
- Produces: `.image` case coverage.

- [ ] **Step 1: Write the failing test**

```swift
// MarkdownPreviewTests/MarkdownRendererImageTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererImageTests`
Expected: FAIL — images render as empty (`defaultVisit` returns `[]`).

- [ ] **Step 3: Write minimal implementation**

Add these to `MarkdownRenderer`:

```swift
    mutating func visitImage(_ image: Image) -> [Block] {
        guard let source = image.source, let url = resolvedURL(for: source) else { return [] }
        return [Block(kind: .image(url: url, altText: image.plainText))]
    }

    private func resolvedURL(for source: String) -> URL? {
        if let url = URL(string: source), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: source, relativeTo: baseURL).absoluteURL
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererImageTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/MarkdownRenderer.swift MarkdownPreviewTests/MarkdownRendererImageTests.swift
git commit -m "feat: render images with base-URL-relative path resolution"
```

---

## Task 8: MarkdownRenderer — block quotes and full-document integration

Adds the one remaining block type (`blockQuote`) and a single test exercising every supported element together in one document, to catch ordering/interaction bugs the isolated tests above can't.

**Files:**
- Modify: `MarkdownPreview/Core/MarkdownRenderer.swift`
- Test: `MarkdownPreviewTests/MarkdownRendererIntegrationTests.swift`

**Interfaces:**
- Consumes: `MarkdownRenderer.render(markdown:baseURL:)`.
- Produces: `.blockQuote` case coverage. This is the last renderer task — `MarkdownRenderer` is feature-complete for the spec's scope after this.

- [ ] **Step 1: Write the failing test**

```swift
// MarkdownPreviewTests/MarkdownRendererIntegrationTests.swift
import XCTest
@testable import MarkdownPreview

final class MarkdownRendererIntegrationTests: XCTestCase {
    func testBlockQuote() {
        let baseURL = URL(fileURLWithPath: "/tmp")
        let blocks = MarkdownRenderer.render(markdown: "> Quoted text.", baseURL: baseURL)

        XCTAssertEqual(blocks.count, 1)
        guard case .blockQuote(let inner) = blocks[0].kind else {
            return XCTFail("Expected block quote, got \(blocks[0].kind)")
        }
        guard case .paragraph(let text) = inner.first?.kind else {
            return XCTFail("Expected paragraph inside block quote")
        }
        XCTAssertEqual(String(text.characters), "Quoted text.")
    }

    func testDocumentWithAllSupportedElements() {
        let source = """
        # Report

        Some **intro** text.

        - Point one
        - Point two

        ```swift
        let x = 1
        ```

        | Col A | Col B |
        | --- | --- |
        | 1 | 2 |

        ![Chart](chart.png)
        """
        let baseURL = URL(fileURLWithPath: "/tmp")
        let blocks = MarkdownRenderer.render(markdown: source, baseURL: baseURL)

        let kinds = blocks.map { block -> String in
            switch block.kind {
            case .heading: return "heading"
            case .paragraph: return "paragraph"
            case .list: return "list"
            case .codeBlock: return "codeBlock"
            case .table: return "table"
            case .image: return "image"
            case .blockQuote: return "blockQuote"
            case .thematicBreak: return "thematicBreak"
            }
        }
        XCTAssertEqual(kinds, ["heading", "paragraph", "list", "codeBlock", "table", "image"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererIntegrationTests`
Expected: `testBlockQuote` FAILs (block quotes render as empty); `testDocumentWithAllSupportedElements` should already PASS given Tasks 3–7.

- [ ] **Step 3: Write minimal implementation**

Add this to `MarkdownRenderer`:

```swift
    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> [Block] {
        let children = blockQuote.children.flatMap { visit($0) }
        return [Block(kind: .blockQuote(blocks: children))]
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownRendererIntegrationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/MarkdownRenderer.swift MarkdownPreviewTests/MarkdownRendererIntegrationTests.swift
git commit -m "feat: render block quotes; add full-document renderer integration test"
```

---

## Task 9: FileWatcher

Watches a file for writes and for delete/rename events, tolerating atomic saves (delete+recreate at the same path within the grace period) without reporting the file missing.

**Files:**
- Create: `MarkdownPreview/Core/FileWatcher.swift`
- Test: `MarkdownPreviewTests/FileWatcherTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `final class FileWatcher { enum Event { case changed; case missing }; init(url: URL, gracePeriod: TimeInterval = 0.5, onEvent: @escaping (Event) -> Void) }`. `onEvent` fires on an arbitrary background queue, not the main queue — callers that touch UI state must dispatch to main themselves ([[Task 10]] does this).

- [ ] **Step 1: Write the failing test**

```swift
// MarkdownPreviewTests/FileWatcherTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/FileWatcherTests`
Expected: FAIL — `FileWatcher` is not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MarkdownPreview/Core/FileWatcher.swift
import Foundation

final class FileWatcher {
    enum Event {
        case changed
        case missing
    }

    private let url: URL
    private let gracePeriod: TimeInterval
    private let onEvent: (Event) -> Void
    private let queue = DispatchQueue(label: "com.sambotello.MarkdownPreview.FileWatcher")
    private var source: DispatchSourceFileSystemObject?
    private var missingWorkItem: DispatchWorkItem?

    init(url: URL, gracePeriod: TimeInterval = 0.5, onEvent: @escaping (Event) -> Void) {
        self.url = url
        self.gracePeriod = gracePeriod
        self.onEvent = onEvent
        start()
    }

    deinit {
        source?.cancel()
    }

    private func start() {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            scheduleMissingCheck()
            return
        }
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        newSource.setEventHandler { [weak self, weak newSource] in
            guard let self, let newSource else { return }
            self.handleEvent(source: newSource)
        }
        newSource.setCancelHandler {
            close(descriptor)
        }
        newSource.resume()
        source = newSource
    }

    private func handleEvent(source: DispatchSourceFileSystemObject) {
        let flags = source.data
        if flags.contains(.delete) || flags.contains(.rename) {
            source.cancel()
            self.source = nil
            scheduleMissingCheck()
        } else {
            missingWorkItem?.cancel()
            onEvent(.changed)
        }
    }

    private func scheduleMissingCheck() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.url.path) {
                self.start()
                self.onEvent(.changed)
            } else {
                self.onEvent(.missing)
            }
        }
        missingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + gracePeriod, execute: workItem)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/FileWatcherTests`
Expected: PASS. These tests are timing-sensitive; if `testToleratesAtomicSaveWithoutReportingMissing` is flaky, increase the wait timeout — the grace period is still exactly 500ms in production regardless of test tuning.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/FileWatcher.swift MarkdownPreviewTests/FileWatcherTests.swift
git commit -m "feat: add FileWatcher with atomic-save-tolerant missing detection"
```

---

## Task 10: MarkdownDocument

The per-window view model tying `MarkdownParser`/`MarkdownRenderer`/`FileWatcher` together into the state the UI switches on.

**Files:**
- Create: `MarkdownPreview/Core/MarkdownDocument.swift`
- Test: `MarkdownPreviewTests/MarkdownDocumentTests.swift`

**Interfaces:**
- Consumes: `MarkdownRenderer.render(markdown:baseURL:)` ([[Task 8]]), `FileWatcher` ([[Task 9]]).
- Produces: `@Observable final class MarkdownDocument { enum State: Equatable { case empty, loaded(blocks: [Block]), fileMissing, unsupportedFile, error(message: String) }; private(set) var state: State; private(set) var url: URL?; func load(url: URL) }`. This is what [[Task 11]]'s views read and call.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownDocumentTests`
Expected: FAIL — `MarkdownDocument` is not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MarkdownPreview/Core/MarkdownDocument.swift
import Foundation
import Observation

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
    private var watcher: FileWatcher?

    private static let supportedExtensions: Set<String> = ["md", "markdown"]

    func load(url: URL) {
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
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

    private func reload() {
        guard let url else { return }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let baseURL = url.deletingLastPathComponent()
            state = .loaded(blocks: MarkdownRenderer.render(markdown: source, baseURL: baseURL))
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -only-testing:MarkdownPreviewTests/MarkdownDocumentTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownPreview/Core/MarkdownDocument.swift MarkdownPreviewTests/MarkdownDocumentTests.swift
git commit -m "feat: add MarkdownDocument view model tying parsing and file watching together"
```

---

## Task 11: Window shell — drop zone, messages, toolbar, and FocusedValue plumbing

First UI task. No XCTest here — per the spec's Testing section, SwiftUI view behavior is verified manually. Each step still ends in a concrete, buildable deliverable.

**Files:**
- Create: `MarkdownPreview/App/FocusedValues.swift`
- Create: `MarkdownPreview/Views/DropZoneView.swift`
- Create: `MarkdownPreview/Views/MessageView.swift`
- Create: `MarkdownPreview/Views/PreviewWindowView.swift`

**Interfaces:**
- Consumes: `MarkdownDocument` ([[Task 10]]).
- Produces: `PreviewWindowView(fileURL: Binding<URL?>)` — the per-window root view [[Task 13]]'s `WindowGroup` instantiates; `FocusedValues.markdownDocument` — the focused-value key [[Task 13]]'s File > Open command reads to decide load-in-place vs. new-window.

- [ ] **Step 1: Add the FocusedValue key**

```swift
// MarkdownPreview/App/FocusedValues.swift
import SwiftUI

private struct MarkdownDocumentFocusedValueKey: FocusedValueKey {
    typealias Value = MarkdownDocument
}

extension FocusedValues {
    var markdownDocument: MarkdownDocument? {
        get { self[MarkdownDocumentFocusedValueKey.self] }
        set { self[MarkdownDocumentFocusedValueKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Add the drop zone and message views**

```swift
// MarkdownPreview/Views/DropZoneView.swift
import SwiftUI

struct DropZoneView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop a markdown file here")
                .font(.title3)
            Text("or use the open button in the toolbar")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

```swift
// MarkdownPreview/Views/MessageView.swift
import SwiftUI

struct MessageView: View {
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Build to verify these compile**

Run: `xcodebuild build -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -configuration Debug`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MarkdownPreview/App/FocusedValues.swift MarkdownPreview/Views/DropZoneView.swift MarkdownPreview/Views/MessageView.swift
git commit -m "feat: add drop zone, message view, and FocusedValue plumbing"
```

- [ ] **Step 5: Add PreviewWindowView**

```swift
// MarkdownPreview/Views/PreviewWindowView.swift
import SwiftUI
import UniformTypeIdentifiers

struct PreviewWindowView: View {
    @Binding var fileURL: URL?
    @State private var document = MarkdownDocument()
    @State private var isImporterPresented = false

    private static let markdownContentTypes: [UTType] =
        ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        content
            .toolbar {
                ToolbarItem {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Open", systemImage: "doc.badge.plus")
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

    @ViewBuilder
    private var content: some View {
        switch document.state {
        case .empty:
            DropZoneView()
        case .loaded(let blocks):
            MarkdownView(blocks: blocks)
        case .fileMissing:
            MessageView(systemImage: "questionmark.folder", message: "File no longer available.")
        case .unsupportedFile:
            MessageView(systemImage: "xmark.circle", message: "Not a markdown file.")
        case .error(let message):
            MessageView(systemImage: "exclamationmark.triangle", message: message)
        }
    }
}
```

- [ ] **Step 6: Build to verify it compiles**

`MarkdownView` doesn't exist yet ([[Task 12]] adds it) — build will fail on that one reference. Confirm the failure is *only* about `MarkdownView`:

Run: `xcodebuild build -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -configuration Debug`
Expected: FAIL, with the only error referencing `MarkdownView` (cannot find `MarkdownView` in scope).

- [ ] **Step 7: Commit**

```bash
git add MarkdownPreview/Views/PreviewWindowView.swift
git commit -m "feat: add PreviewWindowView window shell"
```

---

## Task 12: Block rendering views

Renders `[Block]` as native SwiftUI views. Resolves the build failure left at the end of Task 11.

**Files:**
- Create: `MarkdownPreview/Views/MarkdownView.swift`
- Create: `MarkdownPreview/Views/BlockView.swift`
- Create: `MarkdownPreview/Views/CodeBlockView.swift`
- Create: `MarkdownPreview/Views/ListBlockView.swift`
- Create: `MarkdownPreview/Views/TableBlockView.swift`
- Create: `MarkdownPreview/Views/ImageBlockView.swift`

**Interfaces:**
- Consumes: `Block`, `Block.Kind`, `Block.ListItem` ([[Task 1]]); `MessageView` ([[Task 11]]).
- Produces: `MarkdownView(blocks: [Block])` — the view `PreviewWindowView` ([[Task 11]]) renders for `.loaded` state.

- [ ] **Step 1: Add MarkdownView and BlockView**

```swift
// MarkdownPreview/Views/MarkdownView.swift
import SwiftUI

struct MarkdownView: View {
    let blocks: [Block]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

```swift
// MarkdownPreview/Views/BlockView.swift
import SwiftUI

struct BlockView: View {
    let block: Block

    var body: some View {
        switch block.kind {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(for: level))
                .fontWeight(.bold)
        case .paragraph(let text):
            Text(text)
        case .codeBlock(let code, _):
            CodeBlockView(code: code)
        case .list(let items, let isOrdered):
            ListBlockView(items: items, isOrdered: isOrdered)
        case .table(let headers, let rows):
            TableBlockView(headers: headers, rows: rows)
        case .image(let url, let altText):
            ImageBlockView(url: url, altText: altText)
        case .blockQuote(let blocks):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block)
                }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle().fill(.secondary).frame(width: 3)
            }
        case .thematicBreak:
            Divider()
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }
}
```

- [ ] **Step 2: Add the remaining per-block views**

```swift
// MarkdownPreview/Views/CodeBlockView.swift
import SwiftUI

struct CodeBlockView: View {
    let code: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(8)
        }
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
```

```swift
// MarkdownPreview/Views/ListBlockView.swift
import SwiftUI

struct ListBlockView: View {
    let items: [Block.ListItem]
    let isOrdered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    Text(isOrdered ? "\(index + 1)." : "\u{2022}")
                        .frame(minWidth: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.content)
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            BlockView(block: child)
                        }
                    }
                }
            }
        }
    }
}
```

```swift
// MarkdownPreview/Views/TableBlockView.swift
import SwiftUI

struct TableBlockView: View {
    let headers: [AttributedString]
    let rows: [[AttributedString]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header).fontWeight(.bold)
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                    }
                }
            }
        }
    }
}
```

```swift
// MarkdownPreview/Views/ImageBlockView.swift
import SwiftUI

struct ImageBlockView: View {
    let url: URL
    let altText: String

    var body: some View {
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 480)
        } else {
            MessageView(
                systemImage: "photo.badge.exclamationmark",
                message: altText.isEmpty ? "Image not found" : altText
            )
            .frame(height: 120)
        }
    }
}
```

- [ ] **Step 3: Build to verify everything compiles**

Run: `xcodebuild build -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -configuration Debug`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MarkdownPreview/Views/MarkdownView.swift MarkdownPreview/Views/BlockView.swift MarkdownPreview/Views/CodeBlockView.swift MarkdownPreview/Views/ListBlockView.swift MarkdownPreview/Views/TableBlockView.swift MarkdownPreview/Views/ImageBlockView.swift
git commit -m "feat: render blocks as native SwiftUI views"
```

---

## Task 13: App-level wiring — windows, Cmd+O, and Finder/Dock file opens

Wires `PreviewWindowView` into the app's scene, adds the Cmd+O command routed through the focused document, and registers `.md`/`.markdown` as file types this app can open (Finder "Open With" and Dock-icon drops), per your choice to keep that integration.

**Files:**
- Modify: `MarkdownPreview/MarkdownPreviewApp.swift`
- Create: `MarkdownPreview/App/FileOpenCommand.swift`
- Delete: `MarkdownPreview/ContentView.swift` (default template, superseded by `PreviewWindowView`)

**Interfaces:**
- Consumes: `PreviewWindowView` ([[Task 11]]), `FocusedValues.markdownDocument` ([[Task 11]]).
- Produces: the runnable app — nothing later depends on this task.

- [ ] **Step 1: Register the document type (one-time Xcode GUI step)**

Select the **MarkdownPreview** target > **Info** tab > **Document Types** > click **+**. Set:
- Name: `Markdown Document`
- Extensions: `md, markdown`
- Role: `Viewer`
- Handler Rank: `Alternate` (keeps this app available in Finder's "Open With" and for Dock-icon drops, without claiming the default association for `.md` files)

- [ ] **Step 2: Delete the default template view**

```bash
rm MarkdownPreview/ContentView.swift
```

(Safe to delete outright — it's the unmodified Xcode template, never referenced by anything built in Tasks 1–12.)

- [ ] **Step 3: Add the File > Open command**

```swift
// MarkdownPreview/App/FileOpenCommand.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileOpenCommand: View {
    @FocusedValue(\.markdownDocument) private var focusedDocument
    @Environment(\.openWindow) private var openWindow

    private static let markdownContentTypes: [UTType] =
        ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        Button("Open...") {
            presentOpenPanel()
        }
        .keyboardShortcut("o", modifiers: .command)
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.markdownContentTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let focusedDocument, focusedDocument.url == nil {
            focusedDocument.load(url: url)
        } else {
            openWindow(value: Optional(url))
        }
    }
}
```

- [ ] **Step 4: Wire the scene**

```swift
// MarkdownPreview/MarkdownPreviewApp.swift
import SwiftUI

@main
struct MarkdownPreviewApp: App {
    var body: some Scene {
        WindowGroup(id: "preview", for: URL?.self) { $fileURL in
            PreviewWindowView(fileURL: $fileURL)
                .onOpenURL { url in
                    fileURL = url
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                FileOpenCommand()
            }
        }
    }
}
```

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodebuild build -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -configuration Debug`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MarkdownPreview/MarkdownPreviewApp.swift MarkdownPreview/App/FileOpenCommand.swift
git rm MarkdownPreview/ContentView.swift
git commit -m "feat: wire windows, Cmd+O, and Finder/Dock file opens"
```

---

## Task 14: Manual verification pass

No new code — exercises the finished app against the spec's Testing section and this plan's more uncertain integration points (Finder/Dock routing in particular, since its exact multi-window behavior wasn't verifiable ahead of running the real app).

**Files:** none.

- [ ] **Step 1: Launch and basic drop-zone check**

Build and run from Xcode (Cmd+R). Confirm an empty window opens showing the drop zone with the toolbar's open button visible.

- [ ] **Step 2: Exercise every markdown element**

Create a scratch file exercising every supported element (headings, bold/italic/links/inline code, a fenced code block, an ordered and unordered list with nesting, a table, a local image, a block quote, a thematic break). Drag it onto the window. Confirm each element renders distinctly per the spec's Scope section, and the image displays.

- [ ] **Step 3: Live refresh**

With that file open, edit and save it in another editor (e.g. add a paragraph). Confirm the preview updates automatically, with no manual refresh action.

- [ ] **Step 4: File-missing recovery**

Move the file to a different path (simulating deletion at the original path), and confirm the "File no longer available" message appears — not instantly, but only after roughly half a second. Then move it back to the original path and confirm the preview recovers automatically.

Separately, save the file a few times in an editor that saves atomically (e.g. via `rsync`-style write-then-rename, or just repeated saves in most text editors) and confirm the "File no longer available" message never flashes during normal saves.

- [ ] **Step 5: Multiple windows**

With one file already open, use Cmd+O to open a second, different file. Confirm it opens in a new window, and both windows independently live-update when their respective files change. Confirm dragging a file onto the empty drop-zone window (if one is open) loads it into that same window rather than opening a new one.

- [ ] **Step 6: Cmd+O onto an empty window**

Close all but one window and make sure it's back in the empty drop-zone state. Use Cmd+O to choose a file. Confirm it loads into that same empty window rather than opening a new one.

- [ ] **Step 7: Finder/Dock integration**

With the app already running, double-click a `.md` file in Finder. Confirm it opens (in a new window, or in an existing empty window — either is acceptable). Then drag a different `.md` file directly onto the app's Dock icon and confirm it also opens correctly. Try opening two different files this way in quick succession and confirm each ends up in its own window rather than one overwriting the other.

- [ ] **Step 8: Unsupported file rejection**

Drag a non-markdown file (e.g. a `.txt` or `.png`) onto a window. Confirm the "Not a markdown file" message appears instead of a crash or blank preview.

- [ ] **Step 9: Note and commit any fixes**

If any step above surfaces a bug, fix it in the relevant file from Tasks 1–13, re-run the affected `xcodebuild test`/`build` command, and commit the fix with a message describing what manual verification step caught it.
