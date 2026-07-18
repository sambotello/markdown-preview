// MarkdownPreview/Views/DropZoneView.swift
import SwiftUI

struct DropZoneView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop a markdown file here")
                .font(.title3)
            Text("or use the open button in the toolbar")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
