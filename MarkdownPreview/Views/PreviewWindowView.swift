// MarkdownPreview/Views/PreviewWindowView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PreviewWindowView: View {
    @Binding var fileURL: URL?
    @State private var document = MarkdownDocument()
    @State private var isImporterPresented = false
    @State private var isEditing = false

    private static let markdownContentTypes: [UTType] =
        ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        content
            .navigationTitle(windowTitle)
            .toolbar {
                ToolbarItem {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Open", systemImage: "doc.badge.plus")
                    }
                }
                if document.blocks != nil {
                    ToolbarItem {
                        Button {
                            isEditing.toggle()
                        } label: {
                            Label(isEditing ? "Preview Only" : "Edit", systemImage: isEditing ? "eye" : "square.and.pencil")
                        }
                    }
                }
                if let rawText = document.rawText {
                    ToolbarItem {
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(rawText, forType: .string)
                        } label: {
                            Label("Copy Markdown", systemImage: "doc.on.doc")
                        }
                    }
                }
                if let blocks = document.blocks {
                    ToolbarItem {
                        Button {
                            copyFormatted(blocks: blocks)
                        } label: {
                            Label("Copy Formatted", systemImage: "doc.richtext")
                        }
                    }
                }
                if document.state != .empty {
                    ToolbarItem {
                        Button {
                            document.close()
                            fileURL = nil
                        } label: {
                            Label("Close", systemImage: "xmark.circle")
                        }
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

    private func copyFormatted(blocks: [Block]) {
        let attributed = MarkdownRichTextExporter.makeAttributedString(for: blocks)
        let range = NSRange(location: 0, length: attributed.length)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let rtf = attributed.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let html = try? attributed.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
            pasteboard.setData(html, forType: .html)
        }
        pasteboard.setString(attributed.string, forType: .string)
    }

    private var windowTitle: String {
        guard let name = document.url?.lastPathComponent else { return "MarkdownPreview" }
        return "MarkdownPreview — \(name)"
    }

    @ViewBuilder
    private var content: some View {
        switch document.state {
        case .empty:
            DropZoneView()
        case .loaded(let blocks):
            if isEditing {
                HSplitView {
                    editorPane
                    MarkdownView(blocks: blocks)
                }
            } else {
                MarkdownView(blocks: blocks)
            }
        case .fileMissing:
            MessageView(systemImage: "questionmark.folder", message: "File no longer available.")
        case .unsupportedFile:
            MessageView(systemImage: "xmark.circle", message: "Not a markdown file.")
        case .error(let message):
            MessageView(systemImage: "exclamationmark.triangle", message: message)
        }
    }

    private var editorPane: some View {
        TextEditor(text: Binding(
            get: { document.rawText ?? "" },
            set: { document.updateDraft($0) }
        ))
        .font(.system(.body, design: .monospaced))
    }
}
