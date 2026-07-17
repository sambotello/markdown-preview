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

    func inlineText(_ markup: Markup) -> AttributedString {
        let source = markup.children.map { $0.format() }.joined()
            .trimmingCharacters(in: .whitespaces)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
