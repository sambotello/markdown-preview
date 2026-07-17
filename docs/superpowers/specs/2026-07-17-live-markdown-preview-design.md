# Live Markdown Preview — Design

## Purpose

MarkdownPreview is a macOS app that provides a live, native preview of a
markdown file while it's being edited in another application. The user edits
a `.md` file in their editor of choice; this app watches that file on disk and
re-renders the preview the instant it changes. It is a viewer, not an editor
— there is no in-app editing or saving.

## Scope

Supported markdown elements, rendered distinctly (not as plain text):

- Headers, lists, bold/italic, links, inline code
- Fenced code blocks (monospaced block with background)
- Tables
- Images (loaded from local disk, relative to the source file)

Accepted file extensions: `.md`, `.markdown`.

Out of scope: in-app editing, saving, syntax highlighting within code blocks,
non-local (remote) images, math/LaTeX, diagrams (e.g. Mermaid).

## Architecture

- **SwiftUI app**, no `DocumentGroup` (that implies editing/saving, which this
  app doesn't do). Instead, `WindowGroup(id: "preview", for: URL?.self)` —
  each window scene is keyed by an optional file URL. `nil` means an empty
  drop-zone window.
- **Launch**: one empty window opens, showing a drop zone.
- **Opening files**, any of:
  - Drag & drop a file onto a window — loads into that window.
  - File > Open (Cmd+O) — presents a panel filtered to `.md`/`.markdown`; if
    the current window is empty it loads there, otherwise a new window opens.
  - A title-bar toolbar icon (open-file button) on every window — triggers
    the same File > Open panel as Cmd+O.
  - Dragging file(s) onto the Dock icon / "Open With" — opens a new window
    per file (handled via `onOpenURL`/app delegate).
- **Multiple windows**, each independently watching and previewing its own
  file. Closing a window stops watching that file.

## Components

1. **`MarkdownDocument`** — per-window model holding the file URL, loaded
   source text, parsed blocks, and current state (empty / loading / loaded /
   file-missing / error).
2. **`FileWatcher`** — wraps a `DispatchSourceFileSystemObject` on the file's
   descriptor. Detects writes instantly. Tolerates delete+recreate (as done
   by editors that save atomically) via a 500ms grace period before
   reporting the file as missing.
3. **`MarkdownParser`** — thin wrapper around `swift-markdown`'s
   `Document(parsing:)`, Apple's official CommonMark/GFM parser (the same one
   used internally by DocC), added as a Swift Package dependency.
4. **`MarkdownRenderer`** — a `MarkupVisitor` that walks the AST produced by
   `MarkdownParser` and produces a plain `[Block]` model (headings,
   paragraphs, lists, code blocks, tables, images, etc.). Kept separate from
   SwiftUI so it's testable independent of any view.
5. **SwiftUI views**:
   - `PreviewWindowView` — root view per window. Hosts the toolbar
     (open-file icon) and switches between drop zone / missing-file message /
     error message / rendered preview based on `MarkdownDocument` state.
   - `MarkdownView` plus per-block subviews (`CodeBlockView`, `TableView`,
     `ImageBlockView`, `ListBlockView`, etc.) that render `[Block]`.
6. App-level glue for Dock/"Open With" drops (`onOpenURL` / app delegate),
   routing each incoming URL to a new window.

## Data Flow

1. A file gets into a window (drag & drop, Cmd+O, toolbar button, or
   Dock/"Open With" drop) → `MarkdownDocument` captures the URL and reads the
   file.
2. `MarkdownParser` parses the source into an AST; `MarkdownRenderer` walks
   it into `[Block]`; the view renders them.
3. `FileWatcher` starts monitoring that file's descriptor.
4. On a write event: re-read → re-parse → re-render, instantly, preserving
   scroll position where possible.
5. On a delete/rename event: wait 500ms in case it's an atomic save
   recreating the file at the same path. If it doesn't reappear, switch to
   the "file no longer available" state while keeping the window open and
   still watching, so it recovers automatically if the file comes back.

## Error Handling

- **Initial read fails** (permissions, bad encoding): inline error in that
  window instead of a preview.
- **Unsupported file dropped** (not `.md`/`.markdown`): inline "Not a
  markdown file" message; the drop zone only accepts these extensions.
- **File deleted/renamed/moved while watched**: per Data Flow above — a
  500ms grace period, then "File no longer available" message; window keeps
  watching and recovers automatically if the file reappears.
- **Malformed markdown**: not treated as an error — CommonMark parsers
  (including `swift-markdown`) always produce a best-effort AST, so content
  renders as well as it can.
- **Image referenced in markdown not found on disk**: inline broken-image
  placeholder for that image only, not a window-level error.

## Testing

- The project currently has no test target; this design adds one for the
  core, non-UI logic.
- **Unit tests** (no SwiftUI dependency needed, since `MarkdownRenderer`
  outputs a plain `[Block]` model):
  - `MarkdownParser`/`MarkdownRenderer` against fixture markdown strings —
    assert headings, lists, code blocks, tables, and images parse into the
    expected `Block` values.
  - `FileWatcher` against real temp files — verify write detection, and the
    delete→recreate 500ms grace-period behavior (atomic saves shouldn't flip
    to "missing").
- **Manual verification**: drag in a markdown file exercising every
  supported element; edit it externally and confirm instant live refresh;
  delete/rename it externally and confirm the graceful recovery behavior;
  open multiple files across multiple windows simultaneously.
