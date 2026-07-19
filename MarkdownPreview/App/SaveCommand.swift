// MarkdownPreview/App/SaveCommand.swift
import SwiftUI

struct SaveCommand: View {
    @FocusedValue(\.markdownDocument) private var focusedDocument

    var body: some View {
        Button("Save") {
            focusedDocument?.save()
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(focusedDocument?.isDirty != true)
    }
}
