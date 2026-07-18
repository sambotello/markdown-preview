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
                .font(.system(size: MarkdownTypography.body))
        case .codeBlock(let code, let language):
            CodeBlockView(code: code, language: language)
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
        case 1: return .system(size: MarkdownTypography.heading1)
        case 2: return .system(size: MarkdownTypography.heading2)
        case 3: return .system(size: MarkdownTypography.heading3)
        default: return .system(size: MarkdownTypography.heading4)
        }
    }
}
