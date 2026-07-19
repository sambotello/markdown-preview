# Editor Mode — Design

## Purpose

MarkdownPreview is currently a viewer only: it watches a `.md` file on disk
and re-renders the preview whenever the file changes externally, but has no
way to edit content in-app. This design adds an in-app editing mode: a
toolbar button that splits the window into a Markdown source editor (left)
and the existing live preview (right), so the file can be authored directly
in the app instead of only in an external editor.

## Scope

- Editing applies only to a file already opened in a window (via Cmd+O,
  drag & drop, or Finder/Dock open). Creating a new, untitled/blank document
  is out of scope for this pass.
- Saves are explicit (Cmd+S), not auto-saved. The preview updates live as you
  type, independent of saving.
- The editor/preview split is a per-window toggle (a new toolbar button),
  defaulting to preview-only for every new window.
- The editor pane is a plain, monospaced text editor — no Markdown syntax
  highlighting of the source itself.
- The split divider is user-resizable (50/50 default).
- Unsaved edits are protected against loss from: an external change to the
  file on disk, closing the document (toolbar Close button), and opening a
  different file into the same window. All three prompt before discarding.
- Out of scope: creating new/untitled documents, Markdown source syntax
  highlighting, auto-save, and intercepting the real macOS window close
  (red traffic-light button / Cmd+W) — closing the actual window does not
  prompt to save in this pass.

## Architecture

Extends the existing per-window `MarkdownDocument` view model (rather than
introducing a parallel editor object) with draft/save/dirty state, since
conflict detection between "what's on disk" and "what's being edited"
needs both sides together to reason about. `PreviewWindowView` gains a
purely presentational toggle for whether the editor pane is visible; that
toggle is independent of the document's dirty state, so hiding the editor
never discards an in-progress edit.

## Components

1. **`MarkdownDocument`** (extended) — adds:
   - `savedText: String?` — the last content known to match disk (set on
     every disk load and after a successful save).
   - `isDirty: Bool` — computed as `rawText != nil && rawText != savedText`.
   - `pendingExternalChange: String?` — set when the file changes on disk
     while there are unsaved edits; cleared once the user resolves it.
   - `updateDraft(_ text: String)` — called on every editor keystroke; sets
     `rawText` and re-renders `state` from it immediately.
   - `save() throws` — writes `rawText` to `url`, then sets
     `savedText = rawText`.
   - `keepMyEdits()` / `reloadFromDisk()` — resolve a pending external
     change (see Error Handling).
   - `rawText` keeps its current meaning ("current source text being
     shown/copied") and continues to drive the existing "Copy Markdown"
     button unchanged.
2. **`PreviewWindowView`** (extended) — adds:
   - `@State private var isEditing: Bool` — shows/hides the editor pane;
     only toggleable (and only shown as a toolbar button) when
     `document.state == .loaded`.
   - Split layout: `HSplitView { editor | MarkdownView(blocks:) }` when
     `isEditing`, otherwise today's single-pane `content`.
   - Editor pane: a `TextEditor` with a monospaced font bound to
     `document.rawText`, calling `document.updateDraft(_:)` on change.
   - Alerts for: external-change conflict (Keep My Edits / Reload From
     Disk), unsaved-edits guard on Close/open-new-file (Save / Discard /
     Cancel), and save failures.
3. **`SaveCommand`** (new, `App/SaveCommand.swift`) — follows the existing
   `FileOpenCommand`/`NewWindowCommand` pattern: reads
   `@FocusedValue(\.markdownDocument)`, binds `Cmd+S`, calls
   `focusedDocument?.save()`, disabled when there's no focused document or
   it isn't dirty.
4. **`FileWatcher`** — unchanged. It already fires `.changed` on any write
   to the file, including the app's own saves; reconciliation of
   self-writes vs. genuine external changes happens in `MarkdownDocument`
   by comparing content, not by changing `FileWatcher`. Its `.missing`
   event (file deleted/renamed) is also now dirty-aware in
   `MarkdownDocument` — see Error Handling.

## Data Flow

1. User opens a file as today; `MarkdownDocument` sets both `rawText` and
   `savedText` to the loaded content.
2. User taps the toolbar edit button → `PreviewWindowView` shows the split
   view. The editor's `TextEditor` starts bound to `document.rawText`.
3. On every keystroke, `updateDraft(_:)` updates `rawText` and re-renders
   `state = .loaded(blocks:)` via the same `MarkdownRenderer.render(...)`
   already used for disk loads — the preview pane updates live. No
   debounce for v1; revisit only if typing feels laggy on large documents.
4. `isDirty` becomes true as soon as `rawText != savedText`.
5. User presses Cmd+S (or a future Save toolbar action) → `save()` writes
   `rawText` to disk and sets `savedText = rawText`, clearing `isDirty`.
6. Toggling the editor pane off/on at any point does not touch `rawText`/
   `savedText` — the draft persists across visibility toggles.
7. If the file changes externally while dirty, `MarkdownDocument`
   reconciles the change per Error Handling below rather than reloading
   transparently.

## Error Handling

**External change while editing (`FileWatcher` `.changed` event):**
`FileWatcher` cannot distinguish the app's own save from a genuine external
edit, so `MarkdownDocument` reconciles by content comparison:
1. Read the new disk content.
2. If it equals `savedText` → no-op (this is just the echo of the app's own
   save catching up); ignore.
3. Else if `isDirty` → don't overwrite `rawText`. Set
   `pendingExternalChange` to the new disk content; `PreviewWindowView`
   shows an alert: **"File changed on disk" → Keep My Edits / Reload From
   Disk.**
   - *Keep My Edits* (`keepMyEdits()`): clear `pendingExternalChange`;
     nothing else changes — the document is still dirty and a subsequent
     save overwrites disk with the in-app version.
   - *Reload From Disk* (`reloadFromDisk()`): discard the draft — set
     `rawText`/`savedText` to the new content, re-render, clear
     `pendingExternalChange`.
4. Else (not dirty) → behave exactly as today: reload transparently.

**Closing the document or opening a different file while dirty:**
`PreviewWindowView` checks `document.isDirty` before running the toolbar
Close action, or before accepting a new file via the importer, drag & drop,
or Cmd+O into the same window. If dirty, show a confirmation first:
**Save / Discard / Cancel.**
- *Save*: call `document.save()`, then proceed with the original action.
- *Discard*: proceed without saving.
- *Cancel*: abort; no state change.

**File deleted/renamed externally while dirty (`FileWatcher` `.missing`
event):** today, a `.missing` event unconditionally sets
`state = .fileMissing`, which would hide the editor pane entirely (the
view's state switch shows the "file no longer available" message
regardless of `isEditing`) and strand an in-progress edit behind it. When
`isDirty`, `MarkdownDocument` now ignores `.missing` instead — `rawText`,
`state`, and the editor stay exactly as they are, so the user can keep
editing and save (which recreates the file at that path). When not dirty,
behavior is unchanged from today: transition to `.fileMissing`.

**Out of scope:** the real macOS window close (red traffic-light button /
Cmd+W) is not intercepted in this pass — no unsaved-edits prompt there.

**Save failures** (permissions, disk full, file moved, etc.): `save()`
throws; `PreviewWindowView` surfaces the error via a dismissible alert.
`rawText`/`isDirty` are left untouched so the user can retry the save
without losing the edit.

## Testing

Extends the existing `MarkdownPreviewTests` patterns (unit tests around
`MarkdownDocument`, real-temp-file tests around `FileWatcher` integration):

- **`MarkdownDocument` unit tests** (extending `MarkdownDocumentTests.swift`):
  - `updateDraft(_:)` updates `rawText` and re-renders `state` without
    touching `savedText` or disk.
  - `isDirty` is false right after load, true after `updateDraft` with
    different content, false again after `save()`.
  - `save()` writes `rawText` to a temp file and updates `savedText` to
    match.
  - External-change reconciliation via a real temp-file write (same
    pattern used in `FileWatcherTests`/`MarkdownDocumentTests`), covering:
    (a) not dirty → transparent reload: `rawText`/`savedText` update to the
    new content; (b) dirty + disk content equals `savedText` → no-op, no
    `pendingExternalChange`; (c) dirty + disk content differs →
    `pendingExternalChange` is set and `rawText` is untouched.
  - `keepMyEdits()` clears `pendingExternalChange` without altering
    `rawText`/`savedText`; `reloadFromDisk()` clears it and replaces
    `rawText`/`savedText` with the external content.
  - `save()` failure (e.g. writing to a now-missing directory) leaves
    `rawText`/`isDirty` unchanged and surfaces an error.
  - A `.missing` watcher event while dirty leaves `state` unchanged
    (doesn't transition to `.fileMissing`); the same event while not dirty
    still transitions to `.fileMissing` as today.
- **Manual verification**: toggling the toolbar edit button shows/hides the
  split view without discarding the draft; Cmd+S saves and clears dirty
  state; the Save/Discard/Cancel and Keep-Mine/Reload-From-Disk alerts
  appear and act correctly; the edit toolbar button only appears in
  `.loaded` state; dragging the split divider resizes both panes.
