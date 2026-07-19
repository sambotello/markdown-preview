# MarkdownPreview

A native macOS app that renders Markdown files as SwiftUI views — no WebView — and live-reloads the preview whenever the source file changes on disk.

## Features

- **Live preview** — watches the opened file and re-renders automatically on save (tolerant of atomic saves and brief file-missing windows during editor writes)
- **Native rendering** of headings, paragraphs, ordered/unordered/nested lists, block quotes, thematic breaks, and GitHub-flavored Markdown tables
- **Syntax-highlighted code blocks**, highlighted by language via [Highlightr](https://github.com/raspu/Highlightr)
- **Images**, resolved relative to the source file's base URL, including remote images
- **Copy Formatted** — copy the rendered document as rich text for pasting into apps like Mail or Pages
- Open via `Cmd+O`, drag-and-drop onto the window, Finder "Open With", or as the default double-click handler for `.md`/`.markdown` files
- `Cmd+N` opens an additional window so multiple documents can be previewed side by side
- Window title reflects the currently opened file name

## Requirements

- macOS 14.0+
- Apple Silicon (arm64) — Intel Macs are not supported
- Xcode with Swift 5

## Building

```
xcodebuild -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -configuration Debug build
```

To build and run, open `MarkdownPreview.xcodeproj` in Xcode and use `Cmd+R`.

## Testing

```
xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS'
```

Append `-only-testing:MarkdownPreviewTests/<ClassName>/<testMethodName>` to run a single test.

## Architecture

- `MarkdownPreview/Core` — file loading/watching (`FileWatcher`), Markdown parsing on top of [swift-markdown](https://github.com/swiftlang/swift-markdown) (`MarkdownParser`), the parsed block model (`Block`), rendering logic (`MarkdownRenderer`), and the document view model (`MarkdownDocument`) tying parsing and file watching together
- `MarkdownPreview/Views` — SwiftUI views that present the rendered blocks (`MarkdownView`, `BlockView`, `CodeBlockView`, `ListBlockView`, `TableBlockView`, `ImageBlockView`), plus the drop zone, status messages, rich-text export, and the preview window shell
- `MarkdownPreview/App` — app-level commands and plumbing: opening files (`FileOpenCommand`), new windows (`NewWindowCommand`), and focused-value routing (`FocusedValues`)

## Dependencies

- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown parsing
- [Highlightr](https://github.com/raspu/Highlightr) — code block syntax highlighting
