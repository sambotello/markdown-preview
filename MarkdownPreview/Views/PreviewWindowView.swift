// MarkdownPreview/Views/PreviewWindowView.swift
import SwiftUI
import UniformTypeIdentifiers

struct PreviewWindowView: View {
    @Binding var fileURL: URL?
    @State private var document = MarkdownDocument()
    @State private var isImporterPresented = false

    private static let markdownContentTypes: [UTType] =
        ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        content
            .toolbar {
                ToolbarItem {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Open", systemImage: "doc.badge.plus")
                    }
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: Self.markdownContentTypes) { result in
                if case .success(let url) = result {
                    fileURL = url
                    document.load(url: url)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                fileURL = url
                document.load(url: url)
                return true
            }
            .focusedSceneValue(\.markdownDocument, document)
            .onAppear {
                if let fileURL, document.url == nil {
                    document.load(url: fileURL)
                }
            }
            .onChange(of: fileURL) { _, newURL in
                if let newURL, document.url != newURL {
                    document.load(url: newURL)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch document.state {
        case .empty:
            DropZoneView()
        case .loaded(let blocks):
            MarkdownView(blocks: blocks)
        case .fileMissing:
            MessageView(systemImage: "questionmark.folder", message: "File no longer available.")
        case .unsupportedFile:
            MessageView(systemImage: "xmark.circle", message: "Not a markdown file.")
        case .error(let message):
            MessageView(systemImage: "exclamationmark.triangle", message: message)
        }
    }
}
