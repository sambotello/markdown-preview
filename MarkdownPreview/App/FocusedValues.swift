// MarkdownPreview/App/FocusedValues.swift
import SwiftUI

private struct MarkdownDocumentFocusedValueKey: FocusedValueKey {
    typealias Value = MarkdownDocument
}

extension FocusedValues {
    var markdownDocument: MarkdownDocument? {
        get { self[MarkdownDocumentFocusedValueKey.self] }
        set { self[MarkdownDocumentFocusedValueKey.self] = newValue }
    }
}
