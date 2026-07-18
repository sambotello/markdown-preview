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
        if let url = URL(string: source), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: source, relativeTo: baseURL).absoluteURL
    }

    private mutating func makeListItem(_ item: ListItem) -> Block.ListItem {
        var content = AttributedString("")
        var children: [Block] = []
        for child in item.children {
            if let paragraph = child as? Paragraph {
                content += listItemInlineText(paragraph)
            } else {
                children += visit(child)
            }
        }
        return Block.ListItem(content: content, children: children)
    }

    func inlineText(_ markup: Markup) -> AttributedString {
        let source = markup.children.map { $0.format() }.joined()
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    private func listItemInlineText(_ paragraph: Paragraph) -> AttributedString {
        let source = paragraph.children.map { $0.format() }.joined()
        let dedented = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in String(line.drop(while: { $0 == " " })) }
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: dedented, options: options)) ?? AttributedString(dedented)
    }
}
