// MarkdownPreview/Views/ImageBlockView.swift
import SwiftUI

struct ImageBlockView: View {
    let url: URL
    let altText: String

    var body: some View {
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 480)
        } else {
            MessageView(
                systemImage: "photo.badge.exclamationmark",
                message: altText.isEmpty ? "Image not found" : altText
            )
            .frame(height: 120)
        }
    }
}
