// MarkdownPreview/Views/TableBlockView.swift
import SwiftUI

struct TableBlockView: View {
    let headers: [AttributedString]
    let rows: [[AttributedString]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .font(.system(size: MarkdownTypography.tableText, design: MarkdownTypography.bodyFontDesign))
                        .fontWeight(.bold)
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: MarkdownTypography.tableText, design: MarkdownTypography.bodyFontDesign))
                    }
                }
            }
        }
    }
}
