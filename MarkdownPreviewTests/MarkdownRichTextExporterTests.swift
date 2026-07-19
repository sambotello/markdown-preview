import XCTest
@testable import MarkdownPreview

final class MarkdownRichTextExporterTests: XCTestCase {
    func testBoldItalicAndCodeSpansResolveToDistinctFonts() {
        var text = AttributedString("plain ")
        var bold = AttributedString("bold")
        bold.inlinePresentationIntent = .stronglyEmphasized
        var italic = AttributedString("italic")
        italic.inlinePresentationIntent = .emphasized
        var code = AttributedString("code")
        code.inlinePresentationIntent = .code
        text += bold + AttributedString(" ") + italic + AttributedString(" ") + code

        let blocks: [Block] = [Block(kind: .paragraph(text: text))]
        let attributed = MarkdownRichTextExporter.makeAttributedString(for: blocks)
        let plain = attributed.string

        let boldRange = (plain as NSString).range(of: "bold")
        let italicRange = (plain as NSString).range(of: "italic")
        let codeRange = (plain as NSString).range(of: "code")
        let plainRange = (plain as NSString).range(of: "plain")

        let baseFont = attributed.attribute(.font, at: plainRange.location, effectiveRange: nil) as? NSFont
        let boldFont = attributed.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        let italicFont = attributed.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont
        let codeFont = attributed.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont

        XCTAssertNotNil(baseFont)
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true, "bold span should resolve to a bold font")
        XCTAssertTrue(italicFont?.fontDescriptor.symbolicTraits.contains(.italic) == true, "italic span should resolve to an italic font, even if the body design has no italic face")
        XCTAssertNotEqual(codeFont?.familyName, baseFont?.familyName, "inline code span should resolve to a monospaced font distinct from body text")
    }

    /// Regression test: Cocoa's RTF/HTML writer treats consecutive paragraphs
    /// that ever used `.textBlocks` (e.g. tables) as one nested-block region.
    /// A table following a code block must render as its own isolated table,
    /// not absorb the preceding code block's content into its first cell.
    func testTableFollowingCodeBlockDoesNotAbsorbPrecedingContent() throws {
        let blocks: [Block] = [
            Block(kind: .codeBlock(code: "let x = 1", language: "swift")),
            Block(kind: .table(
                headers: [AttributedString("A"), AttributedString("B")],
                rows: [[AttributedString("1"), AttributedString("2")]]
            )),
        ]

        guard let html = MarkdownRichTextExporter.htmlData(for: blocks),
              let htmlString = String(data: html, encoding: .utf8)
        else {
            return XCTFail("expected non-nil HTML data")
        }

        XCTAssertTrue(htmlString.contains("<table"), "expected a real <table> element")
        // The code text must not appear inside a <td> cell.
        guard let tableRange = htmlString.range(of: "<table") else {
            return XCTFail("no <table> found")
        }
        XCTAssertFalse(htmlString[tableRange.lowerBound...].contains("let x"), "code block content leaked into the table")
    }

    func testExportersProduceNonEmptyOutputForAFullDocument() {
        let blocks: [Block] = [
            Block(kind: .heading(level: 1, text: AttributedString("Title"))),
            Block(kind: .paragraph(text: AttributedString("Body text."))),
            Block(kind: .list(items: [
                Block.ListItem(content: AttributedString("Item"), children: []),
            ], isOrdered: false)),
            Block(kind: .thematicBreak),
            Block(kind: .blockQuote(blocks: [
                Block(kind: .paragraph(text: AttributedString("Quoted."))),
            ])),
            Block(kind: .table(headers: [AttributedString("A")], rows: [[AttributedString("1")]])),
        ]

        guard let rtf = MarkdownRichTextExporter.rtfData(for: blocks) else {
            return XCTFail("expected non-nil RTF data")
        }
        XCTAssertFalse(rtf.isEmpty)

        guard let html = MarkdownRichTextExporter.htmlData(for: blocks) else {
            return XCTFail("expected non-nil HTML data")
        }
        XCTAssertFalse(html.isEmpty)
    }
}
