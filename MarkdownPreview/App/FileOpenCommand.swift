// MarkdownPreview/App/FileOpenCommand.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileOpenCommand: View {
    @FocusedValue(\.markdownDocument) private var focusedDocument
    @Environment(\.openWindow) private var openWindow

    private static let markdownContentTypes: [UTType] =
        ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        Button("Open...") {
            presentOpenPanel()
        }
        .keyboardShortcut("o", modifiers: .command)
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.markdownContentTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let focusedDocument, focusedDocument.url == nil {
            focusedDocument.load(url: url)
        } else {
            openWindow(value: Optional(url))
        }
    }
}
