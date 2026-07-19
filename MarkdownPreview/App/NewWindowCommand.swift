// MarkdownPreview/App/NewWindowCommand.swift
import SwiftUI

struct NewWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Window") {
            openWindow(id: "preview")
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}
