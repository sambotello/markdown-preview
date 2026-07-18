// MarkdownPreview/Views/MarkdownTypography.swift
import CoreGraphics

/// Central place to tune preview font sizes. Change a value here to resize
/// that element everywhere it's rendered.
enum MarkdownTypography {
    static let heading1: CGFloat = 32
    static let heading2: CGFloat = 26
    static let heading3: CGFloat = 22
    static let heading4: CGFloat = 18

    static let body: CGFloat = 16
    static let listItem: CGFloat = 16
    static let tableText: CGFloat = 16
    static let code: CGFloat = 15

    /// Vertical gap between top-level blocks (heading, paragraph, list, etc.).
    static let blockSpacing: CGFloat = 24
}
