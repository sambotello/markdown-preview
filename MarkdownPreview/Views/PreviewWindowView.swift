// MarkdownPreview/Views/PreviewWindowView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PreviewWindowView: View {
    @Binding var fileURL: URL?
    @State private var document = MarkdownDocument()
    @State private var isImporterPresented = false
    @State private var isEditing = false
    @State private var pendingAction: PendingAction?

    private enum PendingAction {
        case close
        case open(URL)
    }

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
                            requestClose()
                        } label: {
                            Label("Close", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: Self.markdownContentTypes) { result in
                if case .success(let url) = result {
                    requestOpen(url: url)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                requestOpen(url: url)
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
            .alert(
                "Unsaved Changes",
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { isPresented in if !isPresented { pendingAction = nil } }
                ),
                presenting: pendingAction
            ) { action in
                Button("Save") {
                    document.save()
                    if document.saveError == nil {
                        resolve(action)
                    } else {
                        pendingAction = nil
                    }
                }
                Button("Discard", role: .destructive) {
                    resolve(action)
                }
                Button("Cancel", role: .cancel) {
                    pendingAction = nil
                }
            } message: { _ in
                Text("This file has unsaved changes. Do you want to save them first?")
            }
            .alert(
                "File Changed on Disk",
                isPresented: Binding(
                    get: { document.pendingExternalChange != nil },
                    set: { isPresented in if !isPresented { document.keepMyEdits() } }
                )
            ) {
                Button("Keep My Edits") {
                    document.keepMyEdits()
                }
                Button("Reload From Disk", role: .destructive) {
                    document.reloadFromDisk()
                }
            } message: {
                Text("This file was changed by another application. Do you want to keep your edits or reload the file from disk?")
            }
            .alert(
                "Couldn't Save File",
                isPresented: Binding(
                    get: { document.saveError != nil },
                    set: { isPresented in if !isPresented { document.dismissSaveError() } }
                )
            ) {
                Button("OK", role: .cancel) {
                    document.dismissSaveError()
                }
            } message: {
                Text(document.saveError ?? "")
            }
    }

    private func requestClose() {
        if document.isDirty {
            pendingAction = .close
        } else {
            performClose()
        }
    }

    private func requestOpen(url: URL) {
        if document.isDirty {
            pendingAction = .open(url)
        } else {
            performOpen(url: url)
        }
    }

    private func resolve(_ action: PendingAction) {
        pendingAction = nil
        switch action {
        case .close:
            performClose()
        case .open(let url):
            performOpen(url: url)
        }
    }

    private func performClose() {
        document.close()
        fileURL = nil
        isEditing = false
    }

    private func performOpen(url: URL) {
        fileURL = url
        document.load(url: url)
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
