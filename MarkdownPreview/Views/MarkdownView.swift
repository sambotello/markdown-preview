// MarkdownPreview/Views/MarkdownView.swift
import SwiftUI

struct MarkdownView: View {
    let blocks: [Block]

    private let horizontalPaddingFraction: CGFloat = 0.1

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: MarkdownTypography.blockSpacing) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        BlockView(block: block)
                    }
                }
                .padding(.horizontal, geometry.size.width * horizontalPaddingFraction)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
