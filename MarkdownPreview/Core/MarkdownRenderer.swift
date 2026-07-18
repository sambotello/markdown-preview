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
        if paragraph.childCount == 1, let image = paragraph.child(at: 0) as? Image {
            let result = visitImage(image)
            if !result.isEmpty {
                return result
            }
        }
        return [Block(kind: .paragraph(text: inlineText(paragraph)))]
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> [Block] {
        [Block(kind: .codeBlock(code: codeBlock.code, language: codeBlock.language))]
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> [Block] {
        [Block(kind: .thematicBreak)]
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> [Block] {
        [Block(kind: .list(items: list.listItems.map { makeListItem($0) }, isOrdered: false))]
    }

    mutating func visitOrderedList(_ list: OrderedList) -> [Block] {
        [Block(kind: .list(items: list.listItems.map { makeListItem($0) }, isOrdered: true))]
    }

    mutating func visitTable(_ table: Table) -> [Block] {
        let headers = Array(table.head.cells).map { inlineText($0) }
        let rows = Array(table.body.rows).map { row in Array(row.cells).map { inlineText($0) } }
        return [Block(kind: .table(headers: headers, rows: rows))]
    }

    mutating func visitImage(_ image: Image) -> [Block] {
        guard let source = image.source, let url = resolvedURL(for: source) else { return [] }
        return [Block(kind: .image(url: url, altText: image.plainText))]
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> [Block] {
        // Detach each child from the block quote before visiting: `inlineText(_:)` formats
        // inline children via `Markup.format()`, which derives its "> " line prefix from the
        // *real* ancestor chain (not just the subtree being formatted). Left attached, every
        // paragraph inside a block quote would leak a "> " prefix into its rendered text.
        let children = blockQuote.children.flatMap { visit($0.detachedFromParent) }
        return [Block(kind: .blockQuote(blocks: children))]
    }

    private func resolvedURL(for source: String) -> URL? {
        if let url = URL(string: source), let scheme = url.scheme {
            // Only `file:` URLs are in scope here — the spec explicitly excludes remote
            // images. A non-file scheme (e.g. `http`/`https`) is treated the same as an
            // unresolvable source (`nil`): `visitImage` returns no block for it, and
            // `visitParagraph`'s existing fallback then renders the paragraph as plain
            // text instead of an image block, rather than silently fetching a remote
            // URL synchronously on the main thread in `ImageBlockView`.
            return scheme == "file" ? url : nil
        }
        return URL(fileURLWithPath: source, relativeTo: baseURL).absoluteURL
    }

    private mutating func makeListItem(_ item: ListItem) -> Block.ListItem {
        var content = AttributedString("")
        var children: [Block] = []
        for child in item.children {
            if let paragraph = child as? Paragraph {
                content += inlineText(paragraph, dedentListMarkerAlignment: true)
            } else {
                children += visit(child)
            }
        }
        return Block.ListItem(content: content, children: children)
    }

    /// - Parameter dedentListMarkerAlignment: When `true`, strips a *leaked*
    ///   list-marker-alignment prefix from each child's formatted output before joining.
    ///   List item continuation lines are indented in the source to align under the
    ///   list marker (e.g. two spaces for `"- "`, three for `"1. "`, and more for each
    ///   further level of nesting), and swift-markdown's `.format()` re-emits that
    ///   alignment padding verbatim — not just on genuine continuation lines, but
    ///   (verified empirically) as a leaked prefix on the first line of *every*
    ///   top-level child formatted here, since each child is formatted in its own
    ///   independent pass that still consults the real list-item ancestor chain. That
    ///   leak is a *constant width* for a given list item (the same leading-space count
    ///   shows up on every child's first line, confirmed empirically across unordered/
    ///   ordered markers and nesting depths) — so it must be stripped per line, before
    ///   joining, rather than only once from a whole joined string: a second child's
    ///   leaked prefix can land mid-string, past any real `"\n"` a whole-string dedent
    ///   pass could still find, once children are joined by a soft break's plain `" "`
    ///   separator (see below) rather than a real `"\n"`.
    ///
    ///   The leak must not be confused with genuine content that happens to start with
    ///   a space: `- **bold** text` parses as `[Strong("bold"), Text(" text")]`, and
    ///   `Text(" text")`'s own formatted output is the leaked prefix *plus* its one
    ///   genuine separator space (the space between `**bold**` and `text` in the
    ///   source) — greedily stripping *all* leading spaces would eat that genuine
    ///   space too, fusing the words into `"boldtext"`. The fix: measure the leak's
    ///   exact width once, from the first non-break child's own first line (that
    ///   child never has genuine leading whitespace of its own, since CommonMark
    ///   already consumes the marker and its trailing space(s) before a list item's
    ///   real content begins), then strip only that many leading spaces — never more —
    ///   from the first line of every child, and from any interior line that follows a
    ///   real `"\n"` within a single child's own multi-line formatted output. Bounding
    ///   the strip to the measured width removes exactly the leak and leaves any
    ///   genuine leading space untouched, producing `"bold text"` rather than
    ///   `"boldtext"` (over-stripped) or `"bold  text"` (under-stripped, i.e. leak left
    ///   in place). Only list items need any of this (`makeListItem` passes `true`);
    ///   headings/paragraphs/table cells aren't indented this way, so they pass `false`
    ///   (the default).
    func inlineText(_ markup: Markup, dedentListMarkerAlignment: Bool = false) -> AttributedString {
        // `Markup.format()` derives its output (including the newline a soft/hard line
        // break contributes) from a continuous formatting pass over a run of siblings.
        // Because each child here is formatted *independently* and the results are then
        // string-joined, calling `.format()` on a `SoftBreak`/`LineBreak` in isolation
        // yields "" — the separator it would normally contribute is never flushed. That
        // silently concatenates the text on either side of the break with no space at all
        // (verified empirically: a two-line paragraph's children are `[Text, SoftBreak,
        // Text]`, and `SoftBreak.format()` alone produces ""). Use each break's own
        // `plainText` instead, which swift-markdown defines as " " for a soft break (a
        // reflowed CommonMark line break) and "\n" for a hard break. A break's `plainText`
        // never carries a leaked list-marker prefix (it isn't produced by `.format()`),
        // so breaks are excluded from the dedent pass below entirely.
        let chunks: [(text: String, isBreak: Bool)] = markup.children.map { child in
            if let softBreak = child as? SoftBreak {
                return (softBreak.plainText, true)
            }
            if let lineBreak = child as? LineBreak {
                return (lineBreak.plainText, true)
            }
            return (child.format(), false)
        }

        let source: String
        if dedentListMarkerAlignment {
            let leakWidth = chunks.first(where: { !$0.isBreak }).flatMap { chunk -> Int? in
                guard let firstLine = chunk.text.split(separator: "\n", omittingEmptySubsequences: false).first
                else { return nil }
                return firstLine.prefix(while: { $0 == " " }).count
            } ?? 0
            source = chunks.map { chunk -> String in
                guard !chunk.isBreak else { return chunk.text }
                return chunk.text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { line -> String in
                        let leadingSpaces = line.prefix(while: { $0 == " " }).count
                        return String(line.dropFirst(min(leadingSpaces, leakWidth)))
                    }
                    .joined(separator: "\n")
            }.joined()
        } else {
            source = chunks.map(\.text).joined()
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
