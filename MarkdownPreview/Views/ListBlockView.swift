// MarkdownPreview/Views/ListBlockView.swift
import SwiftUI

struct ListBlockView: View {
    let items: [Block.ListItem]
    let isOrdered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    Text(isOrdered ? "\(index + 1)." : "\u{2022}")
                        .font(.system(size: MarkdownTypography.listItem))
                        .frame(minWidth: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.content)
                            .font(.system(size: MarkdownTypography.listItem))
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            BlockView(block: child)
                        }
                    }
                }
            }
        }
    }
}
