# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

MarkdownPreview is a native macOS SwiftUI app (bundle id `com.sambotello.MarkdownPreview`, macOS 14.0+ deployment target, Apple Silicon only, Swift 5.0) that renders Markdown files as SwiftUI views — no WebView — and live-reloads the preview when the source file changes on disk. It parses Markdown with [swift-markdown](https://github.com/swiftlang/swift-markdown) and syntax-highlights code blocks with [Highlightr](https://github.com/raspu/Highlightr). A toolbar toggle also enables an editor mode: a plain monospaced Markdown source editor alongside the live preview, with explicit save (`Cmd+S`, never auto-save), dirty tracking, and loss-prevention prompts for unsaved edits (on close, on opening a different file, and on external file changes). A `MarkdownPreviewTests` target exists with unit and integration tests for the parser/renderer/document/file-watcher layers.

## Commands

Build (Debug, for local development):
```
xcodebuild -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -configuration Debug build
```

Build and run: open `MarkdownPreview.xcodeproj` in Xcode and use Cmd+R (there is no CLI-only run path for a macOS app bundle; `xcodebuild build` compiles it, but launching is easiest from Xcode).

List available schemes/targets:
```
xcodebuild -list
```

Run tests:
```
xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS'
```
(add `-only-testing:MarkdownPreviewTests/<ClassName>/<testMethodName>` to run a single test).

## Architecture

`MarkdownPreviewApp.swift` is the `@main` entry point, declaring the `WindowGroup` scene(s) and wiring app-level commands. Code is organized into three groups under `MarkdownPreview/`:

- `Core/` — non-UI logic: `FileWatcher` (watches the opened file, tolerant of atomic saves and brief file-missing windows during editor writes), `MarkdownParser` (wraps swift-markdown), `Block` (the parsed block model), `MarkdownRenderer` (turns parsed content into displayable form), and `MarkdownDocument` (the view model tying parsing, file watching, draft editing, saving, and external-change conflict resolution together — `rawText`/`updateDraft(_:)` hold the live draft, `savedText`/`isDirty` track unsaved state, `save()`/`saveError` handle explicit saves, and `pendingExternalChange`/`keepMyEdits()`/`reloadFromDisk()` resolve conflicts with concurrent external edits)
- `Views/` — SwiftUI presentation: `MarkdownView`/`BlockView` and per-block-type views (`CodeBlockView`, `ListBlockView`, `TableBlockView`, `ImageBlockView`), plus `DropZoneView`, `MessageView`, `MarkdownRichTextExporter` (rich-text "Copy Formatted" export), `MarkdownTypography`, and `PreviewWindowView` (the window shell — also hosts the editor/preview `HSplitView` toggle and the unsaved-edit guard alerts)
- `App/` — app-level commands and plumbing: `FileOpenCommand` (Cmd+O, Finder/Dock opens), `NewWindowCommand` (Cmd+N), `SaveCommand` (Cmd+S), and `FocusedValues`

`.md`/`.markdown` is registered as an importable document type (see `Info.plist`'s `CFBundleDocumentTypes`/`UTImportedTypeDeclarations`), and the app is not sandboxed (needed to load relative local images from arbitrary paths on disk).
