// MarkdownPreview/Views/MarkdownRichTextExporter.swift
import AppKit
import SwiftUI
import Highlightr

/// Converts the full parsed document into a rich-text `NSAttributedString`
/// (and RTF/HTML data) suitable for pasting into word processors like Word
/// or Pages with formatting preserved — headings, bold/italic/code spans,
/// lists, blockquotes, dividers, a real table layout, and embedded images.
///
/// `NSTextBlock` is used only for tables (real column/row layout has no
/// other representation). Dividers/quotes/code deliberately avoid it: Cocoa's
/// RTF/HTML writer treats any paragraph that used `.textBlocks` earlier in
/// the document as still being inside a nested block region, so a table
/// appearing anywhere after one silently absorbs that earlier content into
/// its first cell instead of rendering it as separate paragraphs.
enum MarkdownRichTextExporter {
    static func makeAttributedString(for blocks: [Block]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            append(block: block, depth: 0, isFirst: index == 0, isQuoted: false, into: result)
        }
        return result
    }

    static func rtfData(for blocks: [Block]) -> Data? {
        let attributed = makeAttributedString(for: blocks)
        let range = NSRange(location: 0, length: attributed.length)
        return attributed.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    static func htmlData(for blocks: [Block]) -> Data? {
        let attributed = makeAttributedString(for: blocks)
        let range = NSRange(location: 0, length: attributed.length)
        return try? attributed.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
    }

    // MARK: - Block dispatch

    private static func append(block: Block, depth: Int, isFirst: Bool, isQuoted: Bool, into result: NSMutableAttributedString) {
        let spacingBefore: CGFloat = isFirst ? 0 : MarkdownTypography.blockSpacing
        switch block.kind {
        case .heading(let level, let text):
            appendParagraph(text: text, font: headingFont(level), spacingBefore: spacingBefore, depth: depth, isQuoted: isQuoted, into: result)
        case .paragraph(let text):
            appendParagraph(text: text, font: bodyFont(), spacingBefore: spacingBefore, depth: depth, isQuoted: isQuoted, into: result)
        case .list(let items, let isOrdered):
            appendList(items: items, isOrdered: isOrdered, depth: depth, spacingBefore: spacingBefore, isQuoted: isQuoted, into: result)
        case .thematicBreak:
            appendDivider(spacingBefore: spacingBefore, into: result)
        case .blockQuote(let blocks):
            for (index, child) in blocks.enumerated() {
                append(block: child, depth: depth, isFirst: index == 0 && isFirst, isQuoted: true, into: result)
            }
        case .codeBlock(let code, let language):
            appendCodeBlock(code: code, language: language, spacingBefore: spacingBefore, into: result)
        case .table(let headers, let rows):
            appendTable(headers: headers, rows: rows, spacingBefore: spacingBefore, into: result)
        case .image(let url, let altText):
            appendImage(url: url, altText: altText, spacingBefore: spacingBefore, into: result)
        }
    }

    // MARK: - Block appenders

    private static func appendParagraph(text: AttributedString, font: NSFont, spacingBefore: CGFloat, depth: Int, isQuoted: Bool, into result: NSMutableAttributedString) {
        let content = nsAttributedString(from: text, baseFont: font, tint: isQuoted ? .secondaryLabelColor : .labelColor)
        content.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        let indentLevels = depth + (isQuoted ? 1 : 0)
        if indentLevels > 0 {
            let indent = CGFloat(indentLevels) * 20
            style.headIndent = indent
            style.firstLineHeadIndent = indent
        }
        content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: content.length))
        result.append(content)
    }

    private static func appendList(items: [Block.ListItem], isOrdered: Bool, depth: Int, spacingBefore: CGFloat, isQuoted: Bool, into result: NSMutableAttributedString) {
        let font = listItemFont()
        let indentLevels = depth + (isQuoted ? 1 : 0)
        let markerIndent = CGFloat(indentLevels) * 20
        let textIndent = markerIndent + 20

        for (index, item) in items.enumerated() {
            let style = NSMutableParagraphStyle()
            style.headIndent = textIndent
            style.firstLineHeadIndent = markerIndent
            style.tabStops = [NSTextTab(textAlignment: .left, location: textIndent)]
            style.paragraphSpacingBefore = index == 0 ? spacingBefore : 4

            let marker = isOrdered ? "\(index + 1).\t" : "•\t"
            let color: NSColor = isQuoted ? .secondaryLabelColor : .labelColor
            let line = NSMutableAttributedString(string: marker, attributes: [.font: font, .foregroundColor: color])
            line.append(nsAttributedString(from: item.content, baseFont: font, tint: color))
            line.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: color]))
            line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
            result.append(line)

            for child in item.children {
                append(block: child, depth: depth + 1, isFirst: false, isQuoted: isQuoted, into: result)
            }
        }
    }

    private static func appendDivider(spacingBefore: CGFloat, into result: NSMutableAttributedString) {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.alignment = .center

        let rule = String(repeating: "―", count: 24)
        let content = NSMutableAttributedString(
            string: rule + "\n",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.separatorColor]
        )
        content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: content.length))
        result.append(content)
    }

    private static func appendCodeBlock(code: String, language: String?, spacingBefore: CGFloat, into result: NSMutableAttributedString) {
        let highlightr = Highlightr()
        highlightr?.setTheme(to: "xcode")
        highlightr?.theme.setCodeFont(.monospacedSystemFont(ofSize: MarkdownTypography.code, weight: .regular))

        let codeFont = NSFont.monospacedSystemFont(ofSize: MarkdownTypography.code, weight: .regular)
        let highlighted = highlightr?.highlight(code, as: language)
            ?? NSAttributedString(string: code, attributes: [.font: codeFont])

        let content = NSMutableAttributedString(attributedString: highlighted)
        if !content.string.hasSuffix("\n") {
            content.append(NSAttributedString(string: "\n", attributes: [.font: codeFont]))
        }
        // Character-level background (not a paragraph-level NSTextBlock box)
        // so it can't poison a later table's cell boundaries.
        content.addAttribute(.backgroundColor, value: NSColor(white: 0.95, alpha: 1), range: NSRange(location: 0, length: content.length))

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.headIndent = 8
        style.firstLineHeadIndent = 8
        content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: content.length))
        result.append(content)
    }

    private static func appendTable(headers: [AttributedString], rows: [[AttributedString]], spacingBefore: CGFloat, into result: NSMutableAttributedString) {
        let table = NSTextTable()
        table.numberOfColumns = max(headers.count, 1)
        table.layoutAlgorithm = .automaticLayoutAlgorithm

        func appendRow(_ cells: [AttributedString], rowIndex: Int, isHeader: Bool) {
            let font = isHeader ? tableFont(bold: true) : tableFont(bold: false)
            for (colIndex, cellText) in cells.enumerated() {
                let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: colIndex, columnSpan: 1)
                block.setBorderColor(.separatorColor)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                block.setValue(100.0 / Double(table.numberOfColumns), type: .percentageValueType, for: .width)
                if isHeader {
                    block.backgroundColor = NSColor(white: 0.93, alpha: 1)
                }

                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                style.paragraphSpacingBefore = rowIndex == 0 ? spacingBefore : 0

                let cell = nsAttributedString(from: cellText, baseFont: font, tint: .labelColor)
                cell.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
                cell.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: cell.length))
                result.append(cell)
            }
        }

        appendRow(headers, rowIndex: 0, isHeader: true)
        for (index, row) in rows.enumerated() {
            appendRow(row, rowIndex: index + 1, isHeader: false)
        }
    }

    private static func appendImage(url: URL, altText: String, spacingBefore: CGFloat, into result: NSMutableAttributedString) {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore

        let paragraph: NSMutableAttributedString
        if let nsImage = NSImage(contentsOf: url) {
            let maxWidth: CGFloat = 480
            let size = nsImage.size
            let scale = size.width > 0 ? min(1, maxWidth / size.width) : 1
            let attachment = NSTextAttachment()
            attachment.image = nsImage
            attachment.bounds = CGRect(origin: .zero, size: NSSize(width: size.width * scale, height: size.height * scale))
            paragraph = NSMutableAttributedString(attachment: attachment)
        } else {
            let text = altText.isEmpty ? "[Image not found]" : "[Image: \(altText)]"
            paragraph = NSMutableAttributedString(
                string: text,
                attributes: [.font: bodyFont(), .foregroundColor: NSColor.secondaryLabelColor]
            )
        }
        paragraph.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont()]))
        paragraph.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: paragraph.length))
        result.append(paragraph)
    }

    // MARK: - Fonts & inline runs

    private static func headingFont(_ level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1: size = MarkdownTypography.heading1
        case 2: size = MarkdownTypography.heading2
        case 3: size = MarkdownTypography.heading3
        default: size = MarkdownTypography.heading4
        }
        return .systemFont(ofSize: size, weight: .bold)
    }

    private static func bodyFont() -> NSFont {
        systemFont(size: MarkdownTypography.body, design: MarkdownTypography.bodyFontDesign)
    }

    private static func listItemFont() -> NSFont {
        systemFont(size: MarkdownTypography.listItem, design: MarkdownTypography.bodyFontDesign)
    }

    private static func tableFont(bold: Bool) -> NSFont {
        let font = systemFont(size: MarkdownTypography.tableText, design: MarkdownTypography.bodyFontDesign)
        guard bold else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private static func systemFont(size: CGFloat, design: Font.Design) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        let appKitDesign: NSFontDescriptor.SystemDesign
        switch design {
        case .serif: appKitDesign = .serif
        case .rounded: appKitDesign = .rounded
        case .monospaced: appKitDesign = .monospaced
        default: appKitDesign = .default
        }
        guard let descriptor = base.fontDescriptor.withDesign(appKitDesign) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func nsAttributedString(from text: AttributedString, baseFont: NSFont, tint: NSColor) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for run in text.runs {
            let substring = String(text[run.range].characters)
            guard !substring.isEmpty else { continue }
            let font = resolvedFont(base: baseFont, intent: run.inlinePresentationIntent)
            result.append(NSAttributedString(string: substring, attributes: [.font: font, .foregroundColor: tint]))
        }
        return result
    }

    private static func resolvedFont(base: NSFont, intent: InlinePresentationIntent?) -> NSFont {
        guard let intent else { return base }
        if intent.contains(.code) {
            let descriptor = base.fontDescriptor.withDesign(.monospaced) ?? base.fontDescriptor
            return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
        }
        let manager = NSFontManager.shared
        let wantsBold = intent.contains(.stronglyEmphasized)
        let wantsItalic = intent.contains(.emphasized)

        var font = base
        if wantsBold {
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        if wantsItalic {
            let italicized = manager.convert(font, toHaveTrait: .italicFontMask)
            if italicized.fontDescriptor.symbolicTraits.contains(.italic) {
                font = italicized
            } else {
                // Some designs (e.g. Rounded) have no italic face at all, and
                // NSFontManager silently returns the unstyled font rather than
                // failing — fall back to the default design so emphasis is
                // never silently dropped.
                var fallback = NSFont.systemFont(ofSize: base.pointSize)
                if wantsBold { fallback = manager.convert(fallback, toHaveTrait: .boldFontMask) }
                font = manager.convert(fallback, toHaveTrait: .italicFontMask)
            }
        }
        return font
    }
}
